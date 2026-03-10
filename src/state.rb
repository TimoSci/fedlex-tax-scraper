
# JSON-backed progress tracker so the scraper can resume after interruption.

module State
  def self.load
    if File.exist?(STATE_FILE)
      JSON.parse(File.read(STATE_FILE), symbolize_names: false)
    else
      { 'completed' => [], 'failed' => {}, 'started_at' => Time.now.iso8601 }
    end
  rescue JSON::ParserError
    Log.warn("State file corrupted, starting fresh.")
    { 'completed' => [], 'failed' => {}, 'started_at' => Time.now.iso8601 }
  end

  def self.save(state)
    File.write(STATE_FILE, JSON.pretty_generate(state))
  end

  def self.completed?(state, name)
    state['completed'].include?(name)
  end

  def self.mark_complete(state, name)
    state['completed'] << name unless state['completed'].include?(name)
    state['failed'].delete(name)
    save(state)
  end

  def self.mark_failed(state, name, reason)
    state['failed'][name] ||= []
    state['failed'][name] << { 'time' => Time.now.iso8601, 'reason' => reason }
    save(state)
  end
end
