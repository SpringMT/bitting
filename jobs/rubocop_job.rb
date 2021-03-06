require 'json'
require 'resque'

#Sidekiq.configure_server do |config|
#  config.redis = { url: 'redis://127.0.0.1:6379', namespace: 'sidekiq' }
#end

Resque.redis = 'redis://127.0.0.1:6379'
Resque.redis.namespace = "resque-hook"

class RubocopJob
  #include Sidekiq::Worker
  @queue = :bitting
  #sidekiq_options queue: :bitting, retry: false, backtrace: true

  TOKEN                = ENV['TOKEN']
  GITHUB_HOST          = ENV['GITHUB_HOST'] || 'github.com'
  GITHUB_API_BASE_PATH = ENV['GITHUB_API_BASE_PATH']
  STDOUT.sync = true

  def self.perform(*args)
    queue = JSON.parse(args.first)

    organization    = queue['organization']
    pr_number       = queue['pr_number']
    git_url         = queue['git_url']
    repos_name      = queue['repos_name']
    full_repos_name = queue['full_repos_name']
    branch_name     = queue['branch_name']
    html_url        = queue['html_url']
    sender          = queue['sender']

    Dir.chdir "./tmp" do
      `git clone #{git_url} #{repos_name}_#{pr_number}`
      Dir.chdir "./#{repos_name}_#{pr_number}" do
        execute_rubocop(
          organization:    organization,
          pr_number:       pr_number,
          repos_name:      repos_name,
          full_repos_name: full_repos_name,
          branch_name:     branch_name,
          html_url:        html_url,
          sender:          sender
        )
      end
      FileUtils.rm_r("./#{repos_name}_#{pr_number}")
    end
  end

  private
  def self.execute_rubocop(organization:, pr_number:, repos_name:, full_repos_name:, branch_name:, html_url:, sender:)
    `git checkout #{branch_name}`
    target_files = []
    https = Net::HTTP.new(GITHUB_HOST, '443')
    https.use_ssl = true
    https.start do |h|
      req = Net::HTTP::Get.new("#{GITHUB_API_BASE_PATH}/#{full_repos_name}/pulls/#{pr_number}/files")
      req["Authorization"] = "token #{TOKEN}"
      response = h.request(req)
      p "GET FILES RESPONSE #{response}"
      return  [ 401, { 'Content-Type' => 'text/plain' }, ['GITHUB API FAILED(GET FILES)'] ] unless Net::HTTPSuccess === response
      files = JSON.parse response.body
      target_files = files.select { |f| File.extname(f["filename"]) == '.rb' }.map { |f| f["filename"] }
    end
    return [ 200, { 'Content-Type' => 'text/plain' }, ['target file empty'] ] if target_files.empty?

    rubocop_file = '../../rubocop.yml'
    local_rubocop_file = './.rubocop.yml'
    title_specifix_rubocop_file = "../../#{repos_name}_rubocop.yml"
    if File.exist?(local_rubocop_file)
      rubocop_file = local_rubocop_file
    elsif File.exist?(title_specifix_rubocop_file)
      rubocop_file = title_specifix_rubocop_file
    else

    end
    `../../bin/rubocop -a -D -c #{rubocop_file} #{target_files.join(' ')}`
    commit_result = `git commit -am 'rubocop'`

    return [ 200, { 'Content-Type' => 'text/plain' }, ['UNNECESSARY RUBOCOP PERFECT!'] ] if commit_result.match(/nothing to commit \(working directory clean\)/)

    p `git checkout -b #{branch_name}_rubocop`
    p `git push origin #{branch_name}_rubocop`

    https.start do |h|
      req = Net::HTTP::Post.new("#{GITHUB_API_BASE_PATH}/#{full_repos_name}/pulls")
      req["Authorization"] = "token #{TOKEN}"
      req.body = {
        title: "[Automatic PR] Rubocopnilzed PR from #{full_repos_name}",
        body: "@#{sender} Rubocop Result for #{html_url}",
        head: "#{organization}:#{branch_name}_rubocop",
        base: "#{branch_name}"
      }.to_json
      response = h.request(req)
      return  [ 401, { 'Content-Type' => 'text/plain' }, ['GITHUB API FAILED(CREATE PR)'] ] unless Net::HTTPSuccess === response
    end
    [ 200, { 'Content-Type' => 'text/plain' }, ['SUCCESS'] ]
  end
end
