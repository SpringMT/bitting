web: bundle exec rackup -p $PORT --host $HOST
worker: bundle exec sidekiq -r ./jobs/rubocop_job.rb -C sidekiq.yml
