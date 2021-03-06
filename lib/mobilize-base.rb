require "mobilize-base/version"
require "mobilize-base/extensions/array"
require "mobilize-base/extensions/hash"
require "mobilize-base/extensions/object"
require "mobilize-base/extensions/string"
require "mobilize-base/extensions/time"
require "mobilize-base/extensions/yaml"
#this is the base of the mobilize object, any methods that should be
#made available application-wide go over here
#these also define base variables for Rails
module Mobilize
  module Base
    def Base.root
      begin
        ::Rails.root
      rescue
        ENV['PWD']
      end
    end
    def Base.home_dir
      File.expand_path('..',File.dirname(__FILE__))
    end
    def Base.config_dir
      ENV['MOBILIZE_CONFIG_DIR'] ||= "config/mobilize/"
    end
    def Base.config(config_name)
      config_dir = begin
                     "#{::Rails.root}/#{Base.config_dir}"
                   rescue
                     "#{Base.root}/#{Base.config_dir}"
                   end
      yaml_path = "#{config_dir}#{config_name}.yml"
      if ::File.exists?(yaml_path)
        return ::YAML.load_file(yaml_path)[Base.env]
      else
        raise "Could not find #{config_name}.yml in #{config_dir}"
      end
    end
    def Base.env
      begin
        ::Rails.env
      rescue
        #use MOBILIZE_ENV to manually set your environment when you start your app
        ENV['MOBILIZE_ENV'] || "development"
      end
    end
    def Base.log_dir
      ENV['MOBILIZE_LOG_DIR'] ||= "log/"
    end
    def Base.log_path(log_name)
      log_dir = begin
                  "#{::Rails.root}/#{Base.log_dir}"
                rescue
                  "#{Base.root}/#{Base.log_dir}"
                end
      log_path = "#{log_dir}#{log_name}.log"
      if ::File.exists?(log_dir)
        return log_path
      else
        raise "Could not find #{log_dir} folder for logs"
      end
    end
    def Base.handlers
      Dir.entries(File.dirname(__FILE__) + "/mobilize-base/handlers").select{|e| e.ends_with?(".rb")}.map{|e| e.split(".").first}
    end
  end
end
mongoid_config_path = "#{Mobilize::Base.root}/#{Mobilize::Base.config_dir}mongoid.yml"
if File.exists?(mongoid_config_path)
  require 'mongoid'
  require 'mongoid-grid_fs'
  Mongoid.load!(mongoid_config_path, Mobilize::Base.env)
  require "mobilize-base/models/dataset"
  require "mobilize-base/models/user"
  require "mobilize-base/helpers/runner_helper"
  require "mobilize-base/models/runner"
  require "mobilize-base/helpers/job_helper"
  require "mobilize-base/models/job"
  require "mobilize-base/helpers/stage_helper"
  require "mobilize-base/models/stage"

end
require 'google_drive'
require 'resque'
require "mobilize-base/handlers/resque"
#specify appropriate redis port per resque.yml
Resque.redis = "#{Mobilize::Resque.config['redis_host']}:#{Mobilize::Resque.config['redis_port']}"
require 'popen4'
require "mobilize-base/jobtracker"
require "mobilize-base/handlers/google/gdrive"
require "mobilize-base/handlers/google/gfile"
require "mobilize-base/handlers/google/gbook"
require "mobilize-base/handlers/google/gsheet"
require "mobilize-base/handlers/google/gmail"
require "mobilize-base/extensions/google_drive/acl"
require "mobilize-base/extensions/google_drive/client_login_fetcher"
require "mobilize-base/extensions/google_drive/file"
require "mobilize-base/extensions/google_drive/worksheet"
require "mobilize-base/handlers/gridfs"
