require 'rubocop'
require 'json'

class BundleUpdateApplication
  def call(env)
    body_json = JSON.parse(env["rack.input"].gets)
    organization = body_json.dig('organization', 'login')

    return [ 200, { 'Content-Type' => 'text/plain' }, ['ONLY ALOW PULL REQUEST'] ] unless env['HTTP_X_GITHUB_EVENT'] == 'pull_request'
    return [ 200, { 'Content-Type' => 'text/plain' }, ['THE PR IS NOT OPENED'] ] if body_json["action"] != "opened"
    return [ 200, { 'Content-Type' => 'text/plain' }, ['THIS PR IS AUTO'] ] if body_json['pull_request']['title'].start_with?('[Automatic PR]')
    return [ 200, { 'Content-Type' => 'text/plain' }, ['THIS PR IS AUTO'] ] if body_json['pull_request']['title'].start_with?('Automatic PR')

    queue = {
      organization:    organization,
      pr_number:       body_json['number'],
      git_url:         body_json['repository']['ssh_url'],
      repos_name:      body_json['repository']['name'],
      full_repos_name: body_json['repository']['full_name'],
      branch_name:     body_json['pull_request']['head']['ref'],
      html_url:        body_json['pull_request']['html_url'],
      sender:          body_json['pull_request']['user']['login']
    }.to_json
    Resque.enqueue(BundleUpdateJob, queue)
    [ 200, { 'Content-Type' => 'text/plain' }, ['SUCCESS'] ]
  end
end
