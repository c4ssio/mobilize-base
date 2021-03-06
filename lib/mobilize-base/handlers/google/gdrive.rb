module Mobilize
  module Gdrive
    def Gdrive.config
      Base.config('gdrive')
    end

    def Gdrive.domain
      Gdrive.config['domain']
    end

    def Gdrive.owner_email
      [Gdrive.config['owner']['name'],Gdrive.domain].join("@")
    end

    def Gdrive.owner_name
      Gdrive.config['owner']['name']
    end

    def Gdrive.password(email)
      if email == Gdrive.owner_email
        Gdrive.config['owner']['pw']
      else
        worker = Gdrive.workers(email)
        return worker['pw'] if worker
      end
    end

    def Gdrive.max_api_retries
      Gdrive.config['max_api_retries']
    end

    def Gdrive.max_file_write_retries
      Gdrive.config['max_file_write_retries']
    end

    def Gdrive.file_write_retry_delay
      Gdrive.config['file_write_retry_delay']
    end

    def Gdrive.admins
      Gdrive.config['admins']
    end

    def Gdrive.workers(email=nil)
      if email.nil?
        #divide worker array into equal number of parts
        #as there are deploy servers
        servers = Jobtracker.deploy_servers
        workers = Gdrive.config['workers']
        current_server = Jobtracker.current_server || servers.first
        server_i = servers.index(current_server)
        server_workers = workers.in_groups(servers.length,false)[server_i]
        return server_workers
      else
        Gdrive.workers.select{|w| [w['name'],Gdrive.domain].join("@") == email}.first
      end
    end

    def Gdrive.worker_group_name
      Gdrive.config['worker_group_name']
    end

    def Gdrive.admin_group_name
      Gdrive.config['admin_group_name']
    end

    def Gdrive.worker_emails
      Gdrive.workers.map{|w| [w['name'],Gdrive.domain].join("@")}
    end

    #email management - used to make sure not too many emails get used at the same time
    def Gdrive.slot_worker_by_path(path)
      working_slots = Mobilize::Resque.jobs.map{|j| begin j['args'][1]['gdrive_slot'];rescue;nil;end}.compact.uniq
      Gdrive.workers.sort_by{rand}.each do |w|
        unless working_slots.include?([w['name'],Gdrive.domain].join("@"))
          Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>[w['name'],Gdrive.domain].join("@")})
          return [w['name'],Gdrive.domain].join("@")
        end
      end
      #return false if none are available
      return false
    end

    def Gdrive.unslot_worker_by_path(path)
      begin
        Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>nil})
        return true
      rescue
        return false
      end
    end

    def Gdrive.root(gdrive_slot=nil)
      pw = Gdrive.password(gdrive_slot)
      GoogleDrive.login(gdrive_slot,pw)
    end

    def Gdrive.files(gdrive_slot=nil,params={})
      root = Gdrive.root(gdrive_slot)
      root.files(params)
    end

    def Gdrive.books(gdrive_slot=nil,params={})
      Gdrive.files(gdrive_slot,params).select{|f| f.class==GoogleDrive::Spreadsheet}
    end

    #email management - used to make sure not too many emails get used at the same time
    def Gdrive.slot_worker_by_path(path)
      working_slots = Mobilize::Resque.jobs.map{|j| begin j['args'][1]['gdrive_slot'];rescue;nil;end}.compact.uniq
      Gdrive.workers.sort_by{rand}.each do |w|
        unless working_slots.include?([w['name'],Gdrive.domain].join("@"))
          Mobilize::Resque.set_worker_args_by_path(path,{'gdrive_slot'=>[w['name'],Gdrive.domain].join("@")})
          return [w['name'],Gdrive.domain].join("@")
        end
      end
      #return false if none are available
      return false
    end
  end
end
