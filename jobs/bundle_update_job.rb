require 'json'
require 'resque'
require 'compare_linker'
require 'bundler'

Resque.redis = 'redis://127.0.0.1:6379'
Resque.redis.namespace = "resque-hook"

class BundleUpdateJob
  @queue = :bitting

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

    Dir.chdir "./tmp_bundle_update" do
      `git clone #{git_url} #{repos_name}_#{pr_number}`
      Dir.chdir "./#{repos_name}_#{pr_number}" do
        execute_bundle_update(
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
  def self.execute_bundle_update(organization:, pr_number:, repos_name:, full_repos_name:, branch_name:, html_url:, sender:)
    `git checkout #{branch_name}`

    old_lockfile = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))
    Bundler.with_clean_env do
      `bundle install --gemfile Gemfile --path vendor/bundle`
      `bundle update`
    end
    new_lockfile = Bundler::LockfileParser.new(Bundler.read_file("Gemfile.lock"))

    octokit ||= Octokit::Client.new(access_token: ENV["BUNDLE_UPDATE_OCTOKIT_ACCESS_TOKEN"])
    gem_dictionary = CompareLinker::GemDictionary.new
    formatter = CompareLinker::Formatter::Markdown.new
    comparator = CompareLinker::LockfileComparator.new
    comparator.compare(old_lockfile, new_lockfile)

    compare_links = comparator.updated_gems.map do |gem_name, gem_info|
      if gem_info[:owner].nil?
        finder = CompareLinker::GithubLinkFinder.new(octokit, gem_dictionary)
        finder.find(gem_name)
        gem_info[:homepage_uri] = finder.homepage_uri
        if finder.repo_owner.nil?
          formatter.format(gem_info)
        else
          gem_info[:repo_owner] = finder.repo_owner
          gem_info[:repo_name] = finder.repo_name

          tag_finder = CompareLinker::GithubTagFinder.new(octokit, gem_name, finder.repo_full_name)
          old_tag = tag_finder.find(gem_info[:old_ver])
          new_tag = tag_finder.find(gem_info[:new_ver])

          if old_tag && new_tag
            gem_info[:old_tag] = old_tag.name
            gem_info[:new_tag] = new_tag.name
            formatter.format(gem_info)
          else
            formatter.format(gem_info)
          end
        end
      else
        formatter.format(gem_info)
      end
    end

    commit_result = `git commit -am 'bundle update'`
    
    return [ 200, { 'Content-Type' => 'text/plain' }, ['UNNECESSARY RUBOCOP PERFECT!'] ] if commit_result.match(/nothing to commit \(working directory clean\)/)

    `git checkout -b #{branch_name}_bundle_update`
    `git push origin #{branch_name}_bundle_update`

    https = Net::HTTP.new(GITHUB_HOST, '443')
    https.use_ssl = true
    https.start do |h|
      req = Net::HTTP::Post.new("#{GITHUB_API_BASE_PATH}/#{full_repos_name}/pulls")
      req["Authorization"] = "token #{TOKEN}"
      req.body = {
        title: "[Automatic PR] Bundle Update PR from #{full_repos_name}",
        body: "@#{sender} bundle update result for #{html_url} \n#{compare_links.to_a.join("\n")}",
        head: "#{organization}:#{branch_name}_bundle_update",
        base: "#{branch_name}"
      }.to_json
      response = h.request(req)
      return  [ 401, { 'Content-Type' => 'text/plain' }, ['GITHUB API FAILED(CREATE PR)'] ] unless Net::HTTPSuccess === response
    end
    [ 200, { 'Content-Type' => 'text/plain' }, ['SUCCESS'] ]
  end
end
