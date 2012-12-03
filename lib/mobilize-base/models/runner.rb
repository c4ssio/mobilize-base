module Mobilize
  module Runner
    include Mongoid::Document
    include Mongoid::Timestamps
    field :handler, type: String
    field :path, type: String
    field :active, type: Boolean
    field :status, type: String

    index({ path: 1})

    def headers
      %w{name active trigger status task1 task2 task3 task4 task5}
    end

    def last_cached_at
      r = self
      Dataset.find_or_create_by_path(r.path).last_cached_at
    end

    def worker
      r = self
      Mobilize::Resque.find_worker_by_path(r.path)
    end

    def Runner.find_by_email(email)
      Runner.where(:email=>email).first
    end

    def Runner.find_by_path(path)
      Runner.where(:path=>path).first
    end

    def Runner.perform(id,*args)
      r = Runner.find_by_path(id)
      #get gdrive slot for read
      gdrive_slot = Gdrive.slot_worker(r.worker)
      unless gdrive_slot
        r.update_status("no gdrive slot available for #{r.path}")
        return false
      end
      #make sure any updates to activity are processed first
      #as in when someone runs a "once" job that has completed
      r.update_gsheet(gdrive_slot)
      #read the jobs in the gsheet and update models with news
      r.read_gsheet(gdrive_slot)
      #queue up the jobs that are due and active
      r.jobs.each do |j|
        begin
          if j.active and j.is_due?
            j.tasks.first.enqueue!
          end
        rescue ScriptError, StandardError => exc
          j.update_status("Failed to enqueue #{j.path} at #{Time.now.utc} with #{exc.to_s}")
          j.update_attributes(:active=>false)
        end
      end
      r.update_gsheet(gdrive_slot)
      r.update_attributes(:last_run=>Time.now.utc)
    end

    def dataset
      r = self
      Dataset.find_or_create_by_handler_and_path("gsheet",r.path)
    end

    def Runner.find_or_create_by_handler_and_path(handler,path)
      Runner.where(:handler=>handler,:path=>path).first || Runner.create(:handler=>handler,:path=>path,:active=>true)
    end

    def read_cache
      r = self
      r.dataset.read_cache
    end

    def gsheet(gdrive_slot)
      r = self
      jobs_sheet = Gsheet.find_or_create_by_path(r.path,gdrive_slot)
      jobs_sheet.add_headers(Runner.headers)
      jobs_sheet.delete_sheet1
      return jobs_sheet
    end

    def read_gsheet(gdrive_slot)
      r = self
      gsheet_tsv = r.gsheet(gdrive_slot).to_tsv
      #cache in DB
      r.dataset.write_cache(gsheet_tsv)
      #turn it into a hash array
      gsheet_jobs = gsheet_tsv.tsv_to_hash_array
      #go through each job, update relevant job with its params
      done_jobs = []
      #parse out the jobs and update the Job collection
      gsheet_jobs.each_with_index do |rj,rj_i|
        #skip non-jobs or jobs without required values
        next if (rj['name'].to_s.first == "#" or ['name','active','trigger','task1'].select{|c| rj[c].to_s.strip==""}.length>0)
        j = Job.find_or_create_by_path("#{r.path}/#{rj['name']}")
        #update top line params
        j.update_attributes(:active => rj['active'],
                            :trigger => rj['trigger'])
        if j.is_due?
          Runner.task_count.times do |t_idx|
            task_string = rj["task#{t_idx.to_s}"]
            break if task_string.length==0
            t = Task.find_or_create_by_path("#{j.path}/task#{t_idx}")
            #parse command string, update task with it
            t_handler, call, param_string = [""*3]
            task_string.split(" ").ie do |spls|
              t_handler, call, param_string = [spls.first.split("."), spls[1..-1].strip]
            end
            t.update_attributes(:call=>call, :handler=>t_handler, :param_string=>param_string)
          end
          j.update_status("Updated tasks at #{Time.now.utc}")
        end
        #add this job to list of read ones
        done_jobs << j
      end
      #delete user jobs that are not included in Runner
      (r.jobs.map{|j| j.path} - done_jobs.map{|j| j.path}).each do |rj_path|
        j = Job.find_find_by_path(rj_path)
        j.delete if j
        r.update_status("Deleted job:#{r.name}=>#{j.name}")
      end
      r.update_status(r.name + " jobs read at #{Time.now.utc}")
      return true
    end

    def update_gsheet(gdrive_slot)
      r = self
      jobs_gsheet = r.gsheet(gdrive_slot)
      upd_rows = r.jobs.map{|j| {'name'=>j.name, 'active'=>j.active, 'status'=>j.status} }
      jobs_gsheet.add_or_update_rows(upd_rows)
      r.update_status("#{r.gsheet_name} updated")
      return true
    end

    def jobs(jname=nil)
      r = self
      js = Job.find_all_by_user_id(r.id.to_s)
      if jname
        return js.sel{|j| j.name == jname}.first
      else
        return js
      end
    end

    def update_status(msg)
      r = self
      r.update_attributes(:status=>msg)
      Mobilize::Resque.update_job_status(r.id.to_s,msg)
      return true
    end

    def is_working?
      r = self
      Mobilize::Resque.active_mongo_ids.include?(r.id.to_s)
    end

    def is_due?
      r = self.reload
      return false if r.is_working?
      last_due_time = Time.now.utc - Jobtracker.runner_read_freq
      return true if r.last_run.nil? or r.last_run < last_due_time
    end

    def enqueue!
      r = self
      ::Resque::Job.create("mobilize",Runner,r.path,{})
      return true
    end
  end
end
