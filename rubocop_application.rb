require 'rubocop'
require 'json'

class RubocopApplication
  PROJECT = ENV['PROJECT']
  TOKEN   = ENV['TOKEN']
  GITHUB_HOST= ENV['GITHUB_HOST'] || 'github.com'
  GITHUB_API_BASE_PATH = ENV['GITHUB_API_BASE_PATH']
  STDOUT.sync = true

  def call(env)
    body_json = JSON.parse(env["rack.input"].gets)

    return [ 200, { 'Content-Type' => 'text/plain' }, ['ONLY ALOW PULL REQUEST'] ] unless env['HTTP_X_GITHUB_EVENT'] == 'pull_request'
    return [ 200, { 'Content-Type' => 'text/plain' }, ['THE PR IS NOT OPENED'] ] if body_json["action"] != "opened"
    return [ 200, { 'Content-Type' => 'text/plain' }, ['THIS PR IS AUTO'] ] if body_json['pull_request']['title'] == "Automatic PR. Rubocopnilzed PR from #{PROJECT}"

    @pr_number   = body_json['number']
    @git_url     = body_json['repository']['ssh_url']
    @repos_name  = body_json['repository']['name']
    @branch_name = body_json['pull_request']['head']['ref']
    @html_url    = body_json['pull_request']['html_url']
    @sender      = body_json['pull_request']['user']['login']
    @response    = [ 200, { 'Content-Type' => 'text/plain' }, ['NOTHING'] ]

    Dir.chdir "./tmp" do
      `git clone #{@git_url} #{@repos_name}_#{@pr_number}`
      Dir.chdir "./#{@repos_name}_#{@pr_number}" do
        @response = execute_rubocop
      end
      FileUtils.rm_r("./#{@repos_name}_#{@pr_number}")
    end
    @response
  end

  private
  def execute_rubocop
    `git checkout #{@branch_name}`
    target_files = []
    https = Net::HTTP.new(GITHUB_HOST, '443')
    https.use_ssl = true
    https.start do |h|
      req = Net::HTTP::Get.new("#{GITHUB_API_BASE_PATH}/#{PROJECT}/#{@repos_name}/pulls/#{@pr_number}/files")
      req["Authorization"] = "token #{TOKEN}"
      response = h.request(req)
      p "GET FILES RESPONSE #{response}"
      return  [ 401, { 'Content-Type' => 'text/plain' }, ['GITHUB API FAILED(GET FILES)'] ] unless Net::HTTPSuccess === response
      files = JSON.parse response.body
      target_files = files.select { |f| File.extname(f["filename"]) == '.rb' }.map { |f| f["filename"] }
    end
    return [ 200, { 'Content-Type' => 'text/plain' }, ['target file empty'] ] if target_files.empty?

    rubocop_result = `../../bin/rubocop -a -D -c ../../rubocop.yml #{target_files.join(' ')}`
    commit_result = `git commit -am 'rubocop'`
    return [ 200, { 'Content-Type' => 'text/plain' }, ['UNNECESSARY RUBOCOP PERFECT!'] ] if commit_result.match(/nothing to commit \(working directory clean\)/)

    p `git checkout -b #{@branch_name}_rubocop`
    p `git push origin #{@branch_name}_rubocop`

    https.start do |h|
      req = Net::HTTP::Post.new("#{GITHUB_API_BASE_PATH}/#{PROJECT}/#{@repos_name}/pulls")
      req["Authorization"] = "token #{TOKEN}"
      req.body = {
        title: "Automatic PR. Rubocopnilzed PR from #{PROJECT}",
        body: "@#{@sender} Rubocop Result for #{@html_url}",
        head: "#{PROJECT}:#{@branch_name}_rubocop",
        base: "#{@branch_name}"
      }.to_json
      response = h.request(req)
      return  [ 401, { 'Content-Type' => 'text/plain' }, ['GITHUB API FAILED(CREATE PR)'] ] unless Net::HTTPSuccess === response
    end
    [ 200, { 'Content-Type' => 'text/plain' }, ['SUCCESS'] ]
  end
end
