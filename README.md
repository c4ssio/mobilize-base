Mobilize
========

Mobilize is an end-to-end data transfer workflow manager with:
* a Google Spreadsheets UI through [google-drive-ruby][google_drive_ruby];
* a queue manager through [Resque][resque];
* a persistent caching / database layer through [Mongoid][mongoid];
* gems for data transfers to/from Hive, mySQL, and HTTP endpoints
  (coming soon).

Mobilize-Base includes all the core scheduling and processing
functionality, allowing you to:
* put workers on the Mobilize Resque queue.
* create [Requestors](#section_Requestor) and their associated Google Spreadsheet [Jobspecs](#section_Jobspec);
* poll for [Jobs](#section_Job) on Jobspecs (currently gsheet to gsheet only) and add them to Resque;
* monitor the status of Jobs on a rolling log.

Table Of Contents
-----------------

   * [Install](#section_Install)
      * [Redis](#section_Install_Redis)
      * [MongoDB](#section_Install_MongoDB)
      * [Mobilize-Base](#section_Install_Mobilize-Base)
      * [Default Folders and Files](#section_Install_Folders_and_Files)
   * [Configure](#section_Configure)
      * [Google Drive](#section_Configure_Google_Drive)
      * [Jobtracker](#section_Configure_Jobtracker)
      * [Mongoid](#section_Configure_Mongoid)
      * [Resque](#section_Configure_Resque)
   * [Start](#section_Start)
      * [resque-web](#section_Start_resque-web)
      * [Set Environment](#section_Start_Set_Environment)
      * [Create Requestor](#section_Start_Requestors)
      * [Start Workers](#section_Start_Workers)
      * [Start Jobtracker](#section_Start_Jobtracker)
      * [View Logs](#section_Start_Logs)
      * [Run Test](#section_Start_Test)
   * [Meta](#section_Meta)
   * [Author](#section_Author)

<a name='section_Install'></a>
Install
------------

Mobilize requires Ruby 1.9.3, and has been tested on OSX and Ubuntu. 

<a name='section_Install_Redis'></a>
### Redis

Redis is a pre-requisite for running Resque. 

Please refer to the [Resque Redis Section][redis] for complete
instructions.

<a name='section_Install_MongoDB'></a>
### MongoDB

MongoDB is used to persist caches between reads and writes, keep track
of Requestors and Jobs, and store Datasets that map to endpoints.

Please refer to the [MongoDB Quickstart Page][mongodb_quickstart] to get started.

The settings for database and port are set in config/mongoid.yml
and are best left as default. Please refer to [Configure
Mongoid](#section_Configure_Mongoid) for details.

<a name='section_Install_Mobilize-Base'></a>
### Mobilize-Base

Mobilize-Base contains all of the gems it needs to run. 

add this to your Gemfile:

``` ruby
gem "mobilize-base", "~>1.0"
```

or do

  $ gem install mobilize-base

for a ruby-wide install.

<a name='section_Install_Folders_and_Files'></a>
### Folders and Files

Mobilize requires a config folder and a log folder. 

If you're on Rails, it will use the built-in config and log folders. 

Otherwise, it will use log and config folders in the project folder (the
same one that contains your Rakefile)

### Config File

  $ mkdir config

Additionally, you will need yml files for each of 4 configurations:

  $ touch config/gdrive.yml

  $ touch config/jobtracker.yml

  $ touch config/mongoid.yml

  $ touch config/resque.yml

For now, Mobilize expects config and log folders at the project root
level. (same as the Rakefile)

### Log File

  $ mkdir log

Resque will create a mobilize-resque-<environment>.log in that folder,
and loop over 10 files, 10MB each.

<a name='section_Configure'></a>
Configure
------------

All Mobilize configurations live in files in `config/*.yml`. Samples can
be found below or on github in the [samples][git_samples] folder.


<a name='section_Configure_Google_Drive'></a>
### Configure Google Drive

Google drive needs:
* an owner email address and password. You can set up separate owners
  for different environments as in the below file, which will keep your
mission critical workers from getting rate-limit errors.
* one or more admins with email attributes -- these will be for people
  who should be given write permissions to ALL Mobilize sheets, for
maintenance purposes.
* one or more workers with email and pw attributes -- they will be used
  to queue up google reads and writes. This can be the same as the owner
account for testing purposes or low-volume environments. 

__Mobilize only allows one Resque
worker at a time to use a Google drive worker account for
reading/writing.__

``` yml

development:
  owner:
    email: 'owner_development@host.com'
    pw: "google_drive_password"
  admins:
    - {email: 'admin@host.com'}
  workers:
    - {email: 'worker_development001@host.com', pw: "worker001_google_drive_password"}
    - {email: 'worker_development002@host.com', pw: "worker002_google_drive_password"}
test:
  owner:
    email: 'owner_test@host.com'
    pw: "google_drive_password"
  admins:
    - {email: 'admin@host.com'}
  workers:
    - {email: 'worker_test001@host.com', pw: "worker001_google_drive_password"}
    - {email: 'worker_test002@host.com', pw: "worker002_google_drive_password"}
production:
  owner:
    email: 'owner_production@host.com'
    pw: "google_drive_password"
  admins:
    - {email: 'admin@host.com'}
  workers:
    - {email: 'worker_production001@host.com', pw: "worker001_google_drive_password"}
    - {email: 'worker_production002@host.com', pw: "worker002_google_drive_password"}

```


<a name='section_Jobs'></a>
Jobs
----

What should you run in the background? Anything that takes any time at
all. Slow INSERT statements, disk manipulating, data processing, etc.

At GitHub we use Resque to process the following types of jobs:

* Warming caches
* Counting disk usage
* Building tarballs
* Building Rubygems
* Firing off web hooks
* Creating events in the db and pre-caching them
* Building graphs
* Deleting users
* Updating our search index

As of writing we have about 35 different types of background jobs.

Keep in mind that you don't need a web app to use Resque - we just
mention "foreground" and "background" because they make conceptual
sense. You could easily be spidering sites and sticking data which
needs to be crunched later into a queue.


<a name='section_Jobs_Persistence'></a>
### Persistence

Jobs are persisted to queues as JSON objects. Let's take our `Archive`
example from above. We'll run the following code to create a job:

``` ruby
repo = Repository.find(44)
repo.async_create_archive('masterbrew')
```

The following JSON will be stored in the `file_serve` queue:

``` javascript
{
    'class': 'Archive',
    'args': [ 44, 'masterbrew' ]
}
```

Because of this your jobs must only accept arguments that can be JSON encoded.

So instead of doing this:

``` ruby
Resque.enqueue(Archive, self, branch)
```

do this:

``` ruby
Resque.enqueue(Archive, self.id, branch)
```

This is why our above example (and all the examples in `examples/`)
uses object IDs instead of passing around the objects.

While this is less convenient than just sticking a marshaled object
in the database, it gives you a slight advantage: your jobs will be
run against the most recent version of an object because they need to
pull from the DB or cache.

If your jobs were run against marshaled objects, they could
potentially be operating on a stale record with out-of-date information.

Note that if you queue a job with a hash as an argument the hash
will have its keys stringified when decoded. If you use ActiveSupport
you can call `symbolize_keys!` on the hash to symbolize the keys again
or you can access the values using strings as keys.

<a name='section_Jobs_send_later_async'></a>
### send_later / async

Want something like DelayedJob's `send_later` or the ability to use
instance methods instead of just methods for jobs? See the `examples/`
directory for goodies.

We plan to provide first class `async` support in a future release.


<a name='section_Jobs_Failure'></a>
### Failure

If a job raises an exception, it is logged and handed off to the
`Resque::Failure` module. Failures are logged either locally in Redis
or using some different backend.

For example, Resque ships with Hoptoad support.

Keep this in mind when writing your jobs: you may want to throw
exceptions you would not normally throw in order to assist debugging.


<a name='section_Workers'></a>
Workers
-------

Resque workers are rake tasks that run forever. They basically do this:

``` ruby
start
loop do
  if job = reserve
    job.process
  else
    sleep 5 # Polling frequency = 5 
  end
end
shutdown
```

Starting a worker is simple. Here's our example from earlier:

    $ QUEUE=file_serve rake resque:work

By default Resque won't know about your application's
environment. That is, it won't be able to find and run your jobs - it
needs to load your application into memory.

If we've installed Resque as a Rails plugin, we might run this command
from our RAILS_ROOT:

    $ QUEUE=file_serve rake environment resque:work

This will load the environment before starting a worker. Alternately
we can define a `resque:setup` task with a dependency on the
`environment` rake task:

``` ruby
task "resque:setup" => :environment
```

GitHub's setup task looks like this:

``` ruby
task "resque:setup" => :environment do
  Grit::Git.git_timeout = 10.minutes
end
```

We don't want the `git_timeout` as high as 10 minutes in our web app,
but in the Resque workers it's fine.


<a name='section_Workers_Logging'></a>
### Logging

Workers support basic logging to STDOUT. If you start them with the
`VERBOSE` env variable set, they will print basic debugging
information. You can also set the `VVERBOSE` (very verbose) env
variable.

    $ VVERBOSE=1 QUEUE=file_serve rake environment resque:work

<a name='section_Workers_Process_IDs'></a>
### Process IDs (PIDs)

There are scenarios where it's helpful to record the PID of a resque
worker process.  Use the PIDFILE option for easy access to the PID:

    $ PIDFILE=./resque.pid QUEUE=file_serve rake environment resque:work

<a name='section_Workers_Running_in_the_background'></a>
### Running in the background

(Only supported with ruby >= 1.9). There are scenarios where it's helpful for
the resque worker to run itself in the background (usually in combination with
PIDFILE).  Use the BACKGROUND option so that rake will return as soon as the
worker is started.

    $ PIDFILE=./resque.pid BACKGROUND=yes QUEUE=file_serve \
        rake environment resque:work

<a name='section_Workers_Polling_frequency'></a>
### Polling frequency

You can pass an INTERVAL option which is a float representing the polling frequency. 
The default is 5 seconds, but for a semi-active app you may want to use a smaller value.

    $ INTERVAL=0.1 QUEUE=file_serve rake environment resque:work

<a name='section_Workers_Priorities_and_Queue_Lists'></a>
### Priorities and Queue Lists

Resque doesn't support numeric priorities but instead uses the order
of queues you give it. We call this list of queues the "queue list."

Let's say we add a `warm_cache` queue in addition to our `file_serve`
queue. We'd now start a worker like so:

    $ QUEUES=file_serve,warm_cache rake resque:work

When the worker looks for new jobs, it will first check
`file_serve`. If it finds a job, it'll process it then check
`file_serve` again. It will keep checking `file_serve` until no more
jobs are available. At that point, it will check `warm_cache`. If it
finds a job it'll process it then check `file_serve` (repeating the
whole process).

In this way you can prioritize certain queues. At GitHub we start our
workers with something like this:

    $ QUEUES=critical,archive,high,low rake resque:work

Notice the `archive` queue - it is specialized and in our future
architecture will only be run from a single machine.

At that point we'll start workers on our generalized background
machines with this command:

    $ QUEUES=critical,high,low rake resque:work

And workers on our specialized archive machine with this command:

    $ QUEUE=archive rake resque:work


<a name='section_Workers_Running_All_Queues'></a>
### Running All Queues

If you want your workers to work off of every queue, including new
queues created on the fly, you can use a splat:

    $ QUEUE=* rake resque:work

Queues will be processed in alphabetical order.


<a name='section_Workers_Running_Multiple_Workers'></a>
### Running Multiple Workers

At GitHub we use god to start and stop multiple workers. A sample god
configuration file is included under `examples/god`. We recommend this
method.

If you'd like to run multiple workers in development mode, you can do
so using the `resque:workers` rake task:

    $ COUNT=5 QUEUE=* rake resque:workers

This will spawn five Resque workers, each in its own thread. Hitting
ctrl-c should be sufficient to stop them all.


<a name='section_Workers_Forking'></a>
### Forking

On certain platforms, when a Resque worker reserves a job it
immediately forks a child process. The child processes the job then
exits. When the child has exited successfully, the worker reserves
another job and repeats the process.

Why?

Because Resque assumes chaos.

Resque assumes your background workers will lock up, run too long, or
have unwanted memory growth.

If Resque workers processed jobs themselves, it'd be hard to whip them
into shape. Let's say one is using too much memory: you send it a
signal that says "shutdown after you finish processing the current
job," and it does so. It then starts up again - loading your entire
application environment. This adds useless CPU cycles and causes a
delay in queue processing.

Plus, what if it's using too much memory and has stopped responding to
signals?

Thanks to Resque's parent / child architecture, jobs that use too much memory
release that memory upon completion. No unwanted growth.

And what if a job is running too long? You'd need to `kill -9` it then
start the worker again. With Resque's parent / child architecture you
can tell the parent to forcefully kill the child then immediately
start processing more jobs. No startup delay or wasted cycles.

The parent / child architecture helps us keep tabs on what workers are
doing, too. By eliminating the need to `kill -9` workers we can have
parents remove themselves from the global listing of workers. If we
just ruthlessly killed workers, we'd need a separate watchdog process
to add and remove them to the global listing - which becomes
complicated.

Workers instead handle their own state.


<a name='section_Workers_Parents_and_Children'></a>
### Parents and Children

Here's a parent / child pair doing some work:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Forked 92102 at 1253142769
    92102 resque: Processing file_serve since 1253142769

You can clearly see that process 92099 forked 92102, which has been
working since 1253142769.

(By advertising the time they began processing you can easily use monit
or god to kill stale workers.)

When a parent process is idle, it lets you know what queues it is
waiting for work on:

    $ ps -e -o pid,command | grep [r]esque
    92099 resque: Waiting for file_serve,warm_cache


<a name='section_Workers_Signals'></a>
### Signals

Resque workers respond to a few different signals:

* `QUIT` - Wait for child to finish processing then exit
* `TERM` / `INT` - Immediately kill child then exit
* `USR1` - Immediately kill child but don't exit
* `USR2` - Don't start to process any new jobs
* `CONT` - Start to process new jobs again after a USR2

If you want to gracefully shutdown a Resque worker, use `QUIT`.

If you want to kill a stale or stuck child, use `USR1`. Processing
will continue as normal unless the child was not found. In that case
Resque assumes the parent process is in a bad state and shuts down.

If you want to kill a stale or stuck child and shutdown, use `TERM`

If you want to stop processing jobs, but want to leave the worker running
(for example, to temporarily alleviate load), use `USR2` to stop processing,
then `CONT` to start it again.

<a name='section_Workers_Mysql_Error_MySQL_server_has_gone_away'></a>
### Mysql::Error: MySQL server has gone away

If your workers remain idle for too long they may lose their MySQL
connection. If that happens we recommend using [this
Gist](https://gist.github.com/238999).


<a name='section_The_Front_End'></a>
The Front End
-------------

Resque comes with a Sinatra-based front end for seeing what's up with
your queue.

![The Front End](https://img.skitch.com/20110528-pc67a8qsfapgjxf5gagxd92fcu.png)

<a name='section_The_Front_End_Standalone'></a>
### Standalone

If you've installed Resque as a gem running the front end standalone is easy:

    $ resque-web

It's a thin layer around `rackup` so it's configurable as well:

    $ resque-web -p 8282

If you have a Resque config file you want evaluated just pass it to
the script as the final argument:

    $ resque-web -p 8282 rails_root/config/initializers/resque.rb

You can also set the namespace directly using `resque-web`:

    $ resque-web -p 8282 -N myapp

or set the Redis connection string if you need to do something like select a different database:

    $ resque-web -p 8282 -r localhost:6379:2

<a name='section_Using_The_Front_End_For_Review'></a>

### Using The front end for failures review

Using the front end to review what's happening in the queue
-----------------------------------------------------------
After using Resque for a while, you may have quite a few failed jobs.
Reviewing them by going over pages when showing 20 a page can be a bit hard.

You can change the param in the url (in the failed view only for now), just add per_page=100 and you will see 100 per page.
for example: http://www.your_domain.com/resque/failed?start=20&per_page=200.


<a name='section_The_Front_End_Passenger'></a>

### Passenger

Using Passenger? Resque ships with a `config.ru` you can use. See
Phusion's guide:

Apache: <http://www.modrails.com/documentation/Users%20guide%20Apache.html#_deploying_a_rack_based_ruby_application>
Nginx: <http://www.modrails.com/documentation/Users%20guide%20Nginx.html#deploying_a_rack_app>

<a name='section_The_Front_End_Rack_URLMap'></a>
### Rack::URLMap

If you want to load Resque on a subpath, possibly alongside other
apps, it's easy to do with Rack's `URLMap`:

``` ruby
require 'resque/server'

run Rack::URLMap.new \
  "/"       => Your::App.new,
  "/resque" => Resque::Server.new
```

Check `examples/demo/config.ru` for a functional example (including
HTTP basic auth).

<a name='section_The_Front_End_Rails_3'></a>
### Rails 3

You can also mount Resque on a subpath in your existing Rails 3 app by adding `require 'resque/server'` to the top of your routes file or in an initializer then adding this to `routes.rb`:

``` ruby
mount Resque::Server.new, :at => "/resque"
```

If you use Devise, the following will integrate with your existing admin authentication (assuming you have an Admin Devise scope):

``` ruby
resque_constraint = lambda do |request|
  request.env['warden'].authenticate!({ :scope => :admin })
end
constraints resque_constraint do
  mount Resque::Server.new, :at => "/resque"
end
```



<a name='section_Resque_vs_DelayedJob'></a>
Resque vs DelayedJob
--------------------

How does Resque compare to DelayedJob, and why would you choose one
over the other?

* Resque supports multiple queues
* DelayedJob supports finer grained priorities
* Resque workers are resilient to memory leaks / bloat
* DelayedJob workers are extremely simple and easy to modify
* Resque requires Redis
* DelayedJob requires ActiveRecord
* Resque can only place JSONable Ruby objects on a queue as arguments
* DelayedJob can place _any_ Ruby object on its queue as arguments
* Resque includes a Sinatra app for monitoring what's going on
* DelayedJob can be queried from within your Rails app if you want to
  add an interface

If you're doing Rails development, you already have a database and
ActiveRecord. DelayedJob is super easy to setup and works great.
GitHub used it for many months to process almost 200 million jobs.

Choose Resque if:

* You need multiple queues
* You don't care / dislike numeric priorities
* You don't need to persist every Ruby object ever
* You have potentially huge queues
* You want to see what's going on
* You expect a lot of failure / chaos
* You can setup Redis
* You're not running short on RAM

Choose DelayedJob if:

* You like numeric priorities
* You're not doing a gigantic amount of jobs each day
* Your queue stays small and nimble
* There is not a lot failure / chaos
* You want to easily throw anything on the queue
* You don't want to setup Redis

In no way is Resque a "better" DelayedJob, so make sure you pick the
tool that's best for your app.


<a name='section_Installing_Redis'></a>
Installing Redis
----------------

Resque requires Redis 0.900 or higher.

Resque uses Redis' lists for its queues. It also stores worker state
data in Redis.

<a name='section_Installing_Redis_Homebrew'></a>
#### Homebrew

If you're on OS X, Homebrew is the simplest way to install Redis:

    $ brew install redis
    $ redis-server /usr/local/etc/redis.conf

You now have a Redis daemon running on 6379.

<a name='section_Installing_Redis_Via_Resque'></a>
#### Via Resque

Resque includes Rake tasks (thanks to Ezra's redis-rb) that will
install and run Redis for you:

    $ git clone git://github.com/defunkt/resque.git
    $ cd resque
    $ rake redis:install dtach:install
    $ rake redis:start

Or, if you don't have admin access on your machine:

    $ git clone git://github.com/defunkt/resque.git
    $ cd resque
    $ PREFIX=<your_prefix> rake redis:install dtach:install
    $ rake redis:start

You now have Redis running on 6379. Wait a second then hit ctrl-\ to
detach and keep it running in the background.

The demo is probably the best way to figure out how to put the parts
together. But, it's not that hard.


<a name='section_Resque_Dependencies'></a>
Resque Dependencies
-------------------

    $ gem install bundler
    $ bundle install


<a name='section_Installing_Resque'></a>
Installing Resque
-----------------

<a name='section_Installing_Resque_In_a_Rack_app_as_a_gem'></a>
### In a Rack app, as a gem

First install the gem.

    $ gem install resque

Next include it in your application.

``` ruby
require 'resque'
```

Now start your application:

    rackup config.ru

That's it! You can now create Resque jobs from within your app.

To start a worker, create a Rakefile in your app's root (or add this
to an existing Rakefile):

``` ruby
require 'your/app'
require 'resque/tasks'
```

Now:

    $ QUEUE=* rake resque:work

Alternately you can define a `resque:setup` hook in your Rakefile if you
don't want to load your app every time rake runs.


<a name='section_Installing_Resque_In_a_Rails_2_x_app_as_a_gem'></a>
### In a Rails 2.x app, as a gem

First install the gem.

    $ gem install resque

Next include it in your application

    $ cat config/initializers/load_resque.rb
    require 'resque'

Now start your application:

    $ ./script/server

That's it! You can now create Resque jobs from within your app.

To start a worker, add this to your Rakefile in `RAILS_ROOT`:

``` ruby
require 'resque/tasks'
```

Now:

    $ QUEUE=* rake environment resque:work

Don't forget you can define a `resque:setup` hook in
`lib/tasks/whatever.rake` that loads the `environment` task every time.


<a name='section_Installing_Resque_In_a_Rails_2_x_app_as_a_plugin'></a>
### In a Rails 2.x app, as a plugin

    $ ./script/plugin install git://github.com/defunkt/resque

That's it! Resque will automatically be available when your Rails app
loads.

To start a worker:

    $ QUEUE=* rake environment resque:work

Don't forget you can define a `resque:setup` hook in
`lib/tasks/whatever.rake` that loads the `environment` task every time.


<a name='section_Installing_Resque_In_a_Rails_3_app_as_a_gem'></a>
### In a Rails 3 app, as a gem

First include it in your Gemfile.

    $ cat Gemfile
    ...
    gem 'resque'
    ...

Next install it with Bundler.

    $ bundle install

Now start your application:

    $ rails server

That's it! You can now create Resque jobs from within your app.

To start a worker, add this to a file in `lib/tasks` (ex:
`lib/tasks/resque.rake`):

``` ruby
require 'resque/tasks'
```

Now:

    $ QUEUE=* rake environment resque:work

Don't forget you can define a `resque:setup` hook in
`lib/tasks/whatever.rake` that loads the `environment` task every time.


<a name='section_Configuration'></a>
Configuration
-------------

You may want to change the Redis host and port Resque connects to, or
set various other options at startup.

Resque has a `redis` setter which can be given a string or a Redis
object. This means if you're already using Redis in your app, Resque
can re-use the existing connection.

String: `Resque.redis = 'localhost:6379'`

Redis: `Resque.redis = $redis`

For our rails app we have a `config/initializers/resque.rb` file where
we load `config/resque.yml` by hand and set the Redis information
appropriately.

Here's our `config/resque.yml`:

``` yaml
development: localhost:6379
test: localhost:6379:1
staging: redis1.se.github.com:6379
fi: localhost:6379
production: redis1.ae.github.com:6379
```

Note that separated Redis database should be used for test environment
So that you can flush it and without impacting development environment

And our initializer:

``` ruby
rails_root = Rails.root || File.dirname(__FILE__) + '/../..'
rails_env = Rails.env || 'development'

resque_config = YAML.load_file(rails_root.to_s + '/config/resque.yml')
Resque.redis = resque_config[rails_env]
```

Easy peasy! Why not just use `Rails.root` and `Rails.env`? Because
this way we can tell our Sinatra app about the config file:

    $ RAILS_ENV=production resque-web rails_root/config/initializers/resque.rb

Now everyone is on the same page.

Also, you could disable jobs queueing by setting 'inline' attribute.
For example, if you want to run all jobs in the same process for cucumber, try:

``` ruby
Resque.inline = Rails.env.cucumber?
```


<a name='section_Plugins_and_Hooks'></a>
Plugins and Hooks
-----------------

For a list of available plugins see
<https://wiki.github.com/defunkt/resque/plugins>.

If you'd like to write your own plugin, or want to customize Resque
using hooks (such as `Resque.after_fork`), see
[docs/HOOKS.md](https://github.com/defunkt/resque/blob/master/docs/HOOKS.md).


<a name='section_Namespaces'></a>
Namespaces
----------

If you're running multiple, separate instances of Resque you may want
to namespace the keyspaces so they do not overlap. This is not unlike
the approach taken by many memcached clients.

This feature is provided by the [redis-namespace][rs] library, which
Resque uses by default to separate the keys it manages from other keys
in your Redis server.

Simply use the `Resque.redis.namespace` accessor:

``` ruby
Resque.redis.namespace = "resque:GitHub"
```

We recommend sticking this in your initializer somewhere after Redis
is configured.


<a name='section_Demo'></a>
Demo
----

Resque ships with a demo Sinatra app for creating jobs that are later
processed in the background.

Try it out by looking at the README, found at `examples/demo/README.markdown`.


<a name='section_Monitoring'></a>
Monitoring
----------

<a name='section_Monitoring_god'></a>
### god

If you're using god to monitor Resque, we have provided example
configs in `examples/god/`. One is for starting / stopping workers,
the other is for killing workers that have been running too long.

<a name='section_Monitoring_monit'></a>
### monit

If you're using monit, `examples/monit/resque.monit` is provided free
of charge. This is **not** used by GitHub in production, so please
send patches for any tweaks or improvements you can make to it.


<a name='section_Questions'></a>
Questions
---------

Please add them to the [FAQ](https://github.com/defunkt/resque/wiki/FAQ) or
ask on the Mailing List. The Mailing List is explained further below


<a name='section_Development'></a>
Development
-----------

Want to hack on Resque?

First clone the repo and run the tests:

    git clone git://github.com/defunkt/resque.git
    cd resque
    rake test

If the tests do not pass make sure you have Redis installed
correctly (though we make an effort to tell you if we feel this is the
case). The tests attempt to start an isolated instance of Redis to
run against.

Also make sure you've installed all the dependencies correctly. For
example, try loading the `redis-namespace` gem after you've installed
it:

    $ irb
    >> require 'rubygems'
    => true
    >> require 'redis/namespace'
    => true

If you get an error requiring any of the dependencies, you may have
failed to install them or be seeing load path issues.

Feel free to ping the mailing list with your problem and we'll try to
sort it out.


<a name='section_Contributing'></a>
Contributing
------------

Read the [Contributing][cb] wiki page first. 

Once you've made your great commits:

1. [Fork][1] Resque
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create a [Pull Request](https://help.github.com/pull-requests/) from your branch
5. That's it!


<a name='section_Mailing_List'></a>
Mailing List
------------

To join the list simply send an email to <resque@librelist.com>. This
will subscribe you and send you information about your subscription,
including unsubscribe information.

The archive can be found at <http://librelist.com/browser/resque/>.


<a name='section_Meta'></a>
Meta
----

* Code: `git clone git://github.com/defunkt/resque.git`
* Home: <https://github.com/defunkt/resque>
* Docs: <http://rubydoc.info/gems/resque/frames>
* Bugs: <https://github.com/defunkt/resque/issues>
* List: <resque@librelist.com>
* Chat: <irc://irc.freenode.net/resque>
* Gems: <http://rubygems.org/gems/resque>

This project uses [Semantic Versioning][sv].


<a name='section_Author'></a>
Author
------

Chris Wanstrath :: chris@ozmm.org :: @defunkt

[google_drive_ruby]: https://github.com/gimite/google-drive-ruby
[resque]: https://github.com/defunkt/resque
[mongoid]: http://mongoid.org/en/mongoid/index.html
[resque_redis]: https://github.com/defunkt/resque#section_Installing_Redis
[mongodb_quickstart]: http://www.mongodb.org/display/DOCS/Quickstart
[git_samples]: https://github.ngmoco.com/Ngpipes/mobilize-base/tree/master/lib/samples
