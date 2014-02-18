require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'
require 'redis/namespace'

$dir = File.dirname(File.expand_path(__FILE__))
#set test environment
ENV['MOBILIZE_ENV'] = 'test'
require 'mobilize-base'
$TESTING = true
module TestHelper
  def TestHelper.jobs_at_state( _state )
    if    _state == 'working'
      Mobilize::Resque.workers('working').map{|_worker| _worker.job}.
      select{|_job| _job and _job['payload'] and _job['payload']['args']}
    elsif _state == 'failed'
      Mobilize::Resque.failures.
      select{|_job| _job and _job['payload'] and _job['payload']['args']}
    end.map do |_job|
      { 'path' => _job['payload']['args'].first }
    end
  end
  def TestHelper.confirm_expected_jobs(_expected_fixture_name, _time_limit = 600)
    #clear all failures
    ::Resque::Failure.clear
    _jobs_expected        = TestHelper.load_fixture _expected_fixture_name, {'owner' => TestHelper.owner_user.name }
    _jobs_pending         = _jobs_expected.select{|_job| _job['confirmed_ats'].length < _job['count']}
    _start_time           = Time.now.utc
    _total_time           = 0
    _workers_working      = []
    while ( _jobs_pending.length > 0 or _workers_working.length > 0) and
            _total_time < _time_limit

      _jobs_working                 = TestHelper.jobs_at_state 'working'

      _jobs_failed                  = TestHelper.jobs_at_state 'failed'

      _error_msg                    = ""

      _jobs_unexpected_working      = _jobs_working.reject{|_job_working|
                                      _jobs_expected.select{|_job_expected|
                                      _job_expected['state']                 == 'working' and
                                      _job_working['path'] == _job_expected['path']}.first
                                      }

      if _jobs_unexpected_working.length>0
        _jobs_unexpected_description   = _jobs_unexpected_working.map{|_job| _job['path']}.join(";")
        _error_msg                    += ( _state + ": " + _jobs_unexpected_description + "\n" )
      end

      _jobs_unexpected_failed       = _jobs_failed.reject{|_job_failed|
                                      _jobs_expected.select{|_job_expected|
                                      _job_expected['state']                 == 'failed' and
                                      _job_failed['path']                    == _job_expected['path']}.first
                                    }

      if _jobs_unexpected_failed.length>0
        _jobs_unexpected_description   = _jobs_unexpected_failed.
                                         map{|_job_unexpected_failed| _job_unexpected_failed['path']}.join(";")
        _error_msg                    += ( _state + ": " + _jobs_unexpected_description + "\n" )
      end


      #clear out unexpected paths or there will be failure
      if _error_msg.length>0
        raise "Found unexpected results:\n" + _error_msg
      end

      #now make sure pending jobs get done
      _jobs_expected.each do |_job_expected|
        _start_confirmed_ats              = _job_expected['confirmed_ats']
        _jobs_at_state                    = ( _job_expected['state'] == 'working' ? _jobs_working : _jobs_failed )

        _resque_timestamps                = _jobs_at_state.
                                            select{|_job_at_state| _job_at_state['path']   == _job_expected['path'] }.
                                               map{|_job_at_state| _job_at_state['run_at'] || _job_at_state['failed_at'] }
        _new_timestamps                   = (_resque_timestamps - _start_confirmed_ats).uniq
        if _new_timestamps.length>0 and _job_expected['confirmed_ats'].length < _job_expected['count']
          _job_expected['confirmed_ats'] += _new_timestamps
          puts "#{ Time.now.utc.to_s }: #{ _new_timestamps.length.to_s } " +
               "#{ _job_expected['state'] } added to #{ _job_expected['path'] }; " +
               "total #{ _job_expected['confirmed_ats'].length.to_s } of #{ _job_expected['count'] }"
        end
        _workers_working     = Mobilize::Resque.workers('working').
                               select{|_worker| _worker.job['payload']['class'] != 'Mobilize::Jobtracker'}
      end

      #figure out who's still pending
      _jobs_pending = _jobs_expected.select{|_job_expected| _job_expected['confirmed_ats'].length < _job_expected['count']}
      sleep 1
      _total_time = Time.now.utc - _start_time
      puts "#{ _total_time.to_s } seconds elapsed" if _total_time.to_s.ends_with? "0"
    end
  end

  #test methods
  def TestHelper.restart_test_redis
    TestHelper.stop_test_redis
    if !system("which redis-server")
      raise "** can't find `redis-server` in your path, you need redis to run Resque and Mobilize"
    end
    "redis-server #{Mobilize::Base.root}/test/redis-test.conf".bash
  end

  def TestHelper.stop_test_redis
    processes = `ps -A -o pid,command | grep [r]edis-test`.split($/)
    pids = processes.map { |process| process.split(" ")[0] }
    puts "Killing test redis server..."
    pids.each { |pid| Process.kill("TERM", pid.to_i) }
    puts "removing redis db dump file"
    sleep 5
    `rm -f #{Mobilize::Base.root}/test/dump.rdb #{Mobilize::Base.root}/test/dump-cluster.rdb`
  end

  def TestHelper.set_test_env
    ENV['MOBILIZE_ENV']='test'
    ::Resque.redis="localhost:9736"
    mongoid_config_path = "#{Mobilize::Base.root}/config/mobilize/mongoid.yml"
    Mongoid.load!(mongoid_config_path, Mobilize::Base.env)
  end

  def TestHelper.drop_test_db
    TestHelper.set_test_env
    Mongoid.session(:default).collections.each do |collection| 
      unless collection.name =~ /^system\./
        collection.drop
      end
    end
  end

  def TestHelper.build_test_runner(user_name)
    TestHelper.set_test_env
    u = Mobilize::User.where(:name=>user_name).first
    Mobilize::Jobtracker.update_status("delete old books and datasets")
    # delete any old runner from previous test runs
    gdrive_slot = Mobilize::Gdrive.owner_email
    u.runner.gsheet(gdrive_slot).spreadsheet.delete
    Mobilize::Dataset.find_by_handler_and_path('gbook',u.runner.title).delete
    Mobilize::Jobtracker.update_status("enqueue jobtracker, wait 45s")
    Mobilize::Jobtracker.start
    sleep 45
  end

  def TestHelper.owner_user
    gdrive_slot = Mobilize::Gdrive.owner_email
    user_name = gdrive_slot.split("@").first
    return Mobilize::User.find_or_create_by_name(user_name)
  end

  def TestHelper.load_fixture( _name, _sub_hash = nil)
    #assume yml, check
    _yml_file_path = "#{Mobilize::Base.root}/test/fixtures/#{ _name }.yml"
    _standard_file_path = "#{Mobilize::Base.root}/test/fixtures/#{ _name }"
    _hashes = if File.exists? _yml_file_path
                YAML.load_file _yml_file_path
              elsif File.exists? _standard_file_path
                File.read _standard_file_path
              else
                raise "Could not find #{ _standard_file_path }"
              end
    if _sub_hash
      _hashes.each do |_hash|
        _hash.each do |_key, _value|
          next unless _value.class == String
          _sub_hash.each do |_sub_key, _sub_value |
            _hash[ _key ] = ( _value.gsub "@#{ _sub_key }", _sub_value )
          end
        end
      end
    end
    _hashes
  end

  def TestHelper.write_fixture(fixture_name, target_url, options={})
    u = TestHelper.owner_user
    fixture_raw = TestHelper.load_fixture(fixture_name)
    if options['replace']
      fixture_data = if fixture_raw.class == Array
                     fixture_raw.hash_array_to_tsv
                   elsif fixture_raw.class == String
                     fixture_raw
                   end
      Mobilize::Dataset.write_by_url(target_url,fixture_data,u.name,u.email)
    elsif options['update']
      handler, sheet_path = target_url.split("://")
      raise "update only works for gsheet, not #{handler}" unless handler=='gsheet'
      sheet = Mobilize::Gsheet.find_or_create_by_path(sheet_path,u.email)
      sheet.add_or_update_rows(fixture_raw)
    else
      raise "unknown options #{options.to_s}"
    end
    return true
  end

  #checks output sheet for matching string or minimum length
  def TestHelper.check_output(target_url, options={})
    u = TestHelper.owner_user
    handler, sheet_path = target_url.split("://")
    handler = nil
    sheet = Mobilize::Gsheet.find_by_path(sheet_path,u.email)
    raise "no output found" if sheet.nil?
    output = sheet.to_tsv
    if options['match']
      return true if output == options['match']
    elsif options['min_length']
      return true if output.length >= options['min_length']
    else
      raise "unknown check options #{options.to_s}"
    end
    return true
  end

end
