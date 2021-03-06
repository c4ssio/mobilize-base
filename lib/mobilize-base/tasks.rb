namespace :mobilize do
  desc "Start a Resque worker"
  task :work, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Base.config('jobtracker')['extensions'].each do |e|
      begin
        require e
      rescue Exception=>exc
        #do nothing
      end
    end
    begin
      worker = Resque::Worker.new(Mobilize::Resque.config['queue_name'])
    rescue Resque::NoQueueError
      abort "set QUEUE env var, e.g. $ QUEUE=critical,high rake resque:work"
    end

    puts "Starting worker #{worker}"

    worker.work(ENV['INTERVAL'] || 5) # interval, will block
  end
  desc "Kill all Resque workers"
  task :kill_workers, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_workers
  end
  desc "Kill idle workers"
  task :kill_idle_workers, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_idle_workers
  end
  desc "Make sure there are the correct # of workers, kill if too many"
  task :prep_workers, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.prep_workers
  end
  desc "Restart Resque workers"
  task :restart_workers, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.kill_workers
    sleep 5
    Mobilize::Jobtracker.prep_workers
  end
  desc "Stop Jobtracker"
  task :stop_jobtracker, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.stop!
  end
  desc "Start Jobtracker"
  task :start_jobtracker, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.start
  end
  desc "Restart Jobtracker"
  task :restart_jobtracker, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::Jobtracker.restart!
  end
  desc "Add a user and set up local files"
  task :add_user, :name, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    u = Mobilize::User.find_or_create_by_name(args.name)
  end
  desc "Enqueue a user's runner"
  task :enqueue_user, :name, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    Mobilize::User.where(name: args.name).first.runner.enqueue!
  end
  desc "Enqueue a stage"
  task :enqueue_stage, :path, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    user,job,stage = args.path.split("/")
    Mobilize::Stage.where(path: "Runner_#{user}/jobs/#{job}/#{stage}").first.enqueue!
  end
  desc "Remap http_url for Gbook, Gfile, etc."
  task :remap_http_url, :handler, :path, :http_url, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    dst = Mobilize::Dataset.find_or_create_by_handler_and_path(args.handler,args.path)
    dst.update_attributes(:http_url=>args.http_url)
  end
  desc "kill all old resque web processes, start new one with resque_web.rb extension file"
  task :resque_web, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    port = Mobilize::Base.config('resque')['web_port']
    config_dir = (ENV['MOBILIZE_CONFIG_DIR'] ||= "config/mobilize/")
    full_config_dir = "#{ENV['PWD']}/#{config_dir}"
    resque_web_extension_path = "#{full_config_dir}resque_web.rb"
    #kill any resque-web for now
    `ps aux | grep resque-web | awk '{print $2}' | xargs kill`
    resque_redis_port_args = "#{Mobilize::Base.config('resque')['redis_host']}:#{Mobilize::Base.config('resque')['redis_port']}"
    #determine view folder and override queues and working erbs
    require 'resque/server'
    view_dir = ::Resque::Server.views + "/"
    old_queues_erb_path = view_dir + "queues.erb"
    old_working_erb_path = view_dir + "working.erb"
    gem_dir = Gem::Specification.find_by_name("mobilize-base").gem_dir
    new_queues_erb_path = gem_dir + "/lib/mobilize-base/extensions/resque-server/views/queues.erb"
    new_working_erb_path = gem_dir + "/lib/mobilize-base/extensions/resque-server/views/working.erb"
    [old_queues_erb_path,old_working_erb_path].each{|p| File.delete(p) if File.exists?(p)}
    require 'fileutils'
    FileUtils.copy(new_queues_erb_path,old_queues_erb_path)
    FileUtils.copy(new_working_erb_path,old_working_erb_path)
    sleep 5 #give them time to die
    command = "bundle exec resque-web -r #{resque_redis_port_args} #{resque_web_extension_path}"
    `#{command}`
  end
  desc "create indexes for all base models in mongodb"
  task :create_indexes, :env do |t,args|
    ENV['MOBILIZE_ENV']=args.env
    require 'mobilize-base'
    ["Dataset","Job","Runner","Task","User"].each do |m|
      "Mobilize::#{m}".constantize.create_indexes
    end
  end
  desc "Set up base config and log folders and files"
  task :setup_base do
    config_dir = (ENV['MOBILIZE_CONFIG_DIR'] ||= "config/mobilize/")
    log_dir = (ENV['MOBILIZE_LOG_DIR'] ||= "log/")
    sample_dir = File.dirname(__FILE__) + '/../samples/'
    sample_files = Dir.entries(sample_dir)
    full_config_dir = "#{ENV['PWD']}/#{config_dir}"
    full_log_dir = "#{ENV['PWD']}/#{log_dir}"
    unless File.exists?(full_config_dir)
      puts "creating #{config_dir}"
      `mkdir #{full_config_dir}`
    end
    unless File.exists?(full_log_dir)
      puts "creating #{log_dir}"
      `mkdir #{full_log_dir}`
    end
    sample_files.each do |fname|
      unless File.exists?("#{full_config_dir}#{fname}")
        puts "creating #{config_dir}#{fname}"
        `cp #{sample_dir}#{fname} #{full_config_dir}#{fname}`
      end
    end
  end
end
