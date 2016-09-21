class HelloApplication
  def call(env)
    return [ 200, { 'Content-Type' => 'text/plain' }, ['HELLO WORLD'] ]
  end
end
