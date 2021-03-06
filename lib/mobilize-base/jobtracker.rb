module Mobilize
  module Jobtracker
    #adds convenience methods
    require "#{File.dirname(__FILE__)}/helpers/jobtracker_helper"

    def Jobtracker.max_run_time_workers
      #return workers who have been cranking away for 6+ hours
        workers = Jobtracker.workers('working').select do |w|
            w.job['run_at'].to_s.length>0 and 
              (Time.now.utc - Time.parse(w.job['run_at'])) > Jobtracker.max_run_time
        end
        return workers
    end

    def Jobtracker.start_worker(count=nil)
      Resque.start_workers(count)
    end

    def Jobtracker.kill_workers(count=nil)
      Resque.kill_workers(count)
    end

    def Jobtracker.run_notifications
      if Jobtracker.notif_due?
        notifs = []
        if Jobtracker.failures.length>0
          failure_hash = Resque.new_failures_by_email
          failure_hash.each do |email,stage_paths|
            n = {}
            n['subject'] = "#{stage_paths.keys.length.to_s} new failed jobs, #{stage_paths.values.map{|v| v.values}.flatten.sum.to_s} failures"
            #one row per exception type, with the job name
            n['body'] = stage_paths.map do |path,exceptions| 
                                          exceptions.map do |exc_to_s,times| 
                                            [path," : ",exc_to_s,", ",times," times"].join
                                          end
                                        end.flatten.join("\n\n")
            u = User.where(:name=>email.split("@").first).first
            if u
              runner_dst = Dataset.find_by_url("gsheet://#{u.runner.path}")
              n['body'] += "\n\n#{runner_dst.http_url}" if runner_dst and runner_dst.http_url
            end
            n['to'] = email
            #uncomment to receive a copy of emails sent to users
            #n['bcc'] = [Gdrive.admin_group_name,Gdrive.domain].join("@")
            notifs << n
          end
        end
        lws = Jobtracker.max_run_time_workers
        if lws.length>0
          bod = begin
                  lws.map{|w| w.job['payload']['args']}.first.join("\n")
                rescue
                  "Failed to get job names"
                end
          n = {}
          n['subject'] = "#{lws.length.to_s} max run time jobs"
          n['body'] = bod
          n['to'] = [Gdrive.admin_group_name,Gdrive.domain].join("@")
          notifs << n
        end
        #deliver each email generated
        notifs.each do |notif|
          begin
            Gmail.write(notif).deliver
          rescue
            #log email on failure
            Jobtracker.update_status("Failed to deliver #{notif.to_s}")
          end
        end
        #update notification time so JT knows to wait a while
        Jobtracker.last_notification = Time.now.utc.to_s
        Jobtracker.update_status("Sent notification at #{Jobtracker.last_notification}")
      end
      return true
    end

    def Jobtracker.deploy_servers
      servers = begin
                  deploy_file_path = "#{Base.root}/config/deploy/#{Base.env}.rb"
                  server_line = File.readlines(deploy_file_path).select{|l| l.strip.starts_with?("role ")}.first
                  #reject arguments that start w symbols
                  server_strings = server_line.split(",")[1..-1].reject{|t| t.strip.starts_with?(":")}
                  server_strings.map{|ss| ss.gsub("'","").gsub('"','').strip}
                rescue
                  ["127.0.0.1"]
                end
      servers
    end

    def Jobtracker.current_server
      #try to use configured name first
      begin;return Mobilize::Base.config('jobtracker')['server_name'];rescue;end
      begin
        Socket.gethostbyname(Socket.gethostname).first
      rescue
        nil
      end
    end

    def Jobtracker.perform( _id,*_args )
      while Jobtracker.status != 'stopping'
        _users = User.all
        Jobtracker.run_notifications
        #run throush all users randomly
        #so none are privileged on JT restarts
        _users.sort_by{rand}.each do |_user|
          _runner                   = _user.runner
          Jobtracker.update_status( "Checking #{ _runner.path}" ) if _runner.is_on_server?
          #check for run_now file
          _user_dir                 = "/home/#{ _user.name }/"
          _run_now_dir              = "#{ _user_dir }mobilize/"
          _run_now_path             = "#{ _run_now_dir }run_now"
          if File.exists? _user_dir
            if `sudo ls #{ _run_now_dir }`.split("\n").include? "run_now"
              #delete user's run now file
              `sudo rm -rf #{ _run_now_path }`
              _run_now = true
            else
              false
            end
            _runner.force_due if _run_now
          end
          if _runner.is_due?
            _runner.enqueue!
            Jobtracker.update_status "Enqueued #{ _runner.path }"
          end
        end
        sleep 5
      end
      Jobtracker.update_status "told to stop"
      return true
    end
  end
end
