
# Timestamped logging to stdout and a persistent log file.

module Log
  def self.setup
    FileUtils.mkdir_p(OUTPUT_DIR)
    @logfile = File.open(LOG_FILE, 'a')
  end

  def self.write(level, message)
    line = "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [#{level.upcase.ljust(5)}] #{message}"
    puts line
    @logfile&.puts(line)
    @logfile&.flush
  end

  def self.info(msg)  = write('info',  msg)
  def self.warn(msg)  = write('warn',  msg)
  def self.error(msg) = write('error', msg)
  def self.ok(msg)    = write('ok',    msg)
end
