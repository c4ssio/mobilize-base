require 'test_helper'
describe Mobilize do

  it "runs integration test" do

    puts "restart test redis"
    TestHelper.restart_test_redis
    TestHelper.drop_test_db

    puts "restart workers"
    Mobilize::Jobtracker.restart_workers!

    _user                          = TestHelper.owner_user
    _runner                        = _user.runner
    _user_name                     = _user.name
    _gdrive_slot                   = _user.email

    puts "build test runner"
    TestHelper.build_test_runner     _user_name
    assert Mobilize::Jobtracker.workers.length == Mobilize::Resque.config['max_workers'].to_i

    puts "add base1_stage1.in sheet"
    _input_fixture_name            = "base1_stage1.in"
    _input_target_url              = "gsheet://#{ _runner.title }/#{ _input_fixture_name }"
    TestHelper.write_fixture         _input_fixture_name, _input_target_url, 'replace' => true

    puts "add jobs sheet with integration jobs"
    _jobs_fixture_name             = "integration_jobs"
    _jobs_target_url               = "gsheet://#{ _runner.title}/jobs"
    TestHelper.write_fixture         _jobs_fixture_name, _jobs_target_url, 'update' => true

    puts "wait for stages"
    Mobilize::Jobtracker.start
    #wait for stages to complete
    _expected_fixture_name         = "integration_expected"
    TestHelper.confirm_expected_jobs _expected_fixture_name, 120
    #stop jobtracker
    Mobilize::Jobtracker.stop!

    puts "jobtracker posted test sheet data to test destination, and checksum succeeded?"
    _tsv_hash                      = {}
    ["base1_stage1.in", "base1_stage2.out"].each do |_sheet_name|
      _url                         = "gsheet://#{ _runner.title }/#{ _sheet_name }"
      _data                        = Mobilize::Dataset.read_by_url _url, _user_name, _gdrive_slot
      assert TestHelper.check_output( _url, 'min_length' => 10 ) == true
      _tsv_hash[ _sheet_name ]     = _data
    end

    assert _tsv_hash["base1_stage2.out"] == _tsv_hash["base1_stage1.in"]

    _err_url                       = "gsheet://#{ _runner.title}/base2_stage1.err"
    _err_response                  = "Unable to parse stage params, " +
                                     "make sure you don't have issues with your quotes, commas, or colons."

    assert TestHelper.check_output( _err_url, 'match' => _err_response) == true

    Mobilize::Jobtracker.kill_workers
  end
end
