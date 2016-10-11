module RetryHelper
  RETRY_ATTEMPTS = 4 # 1 + 4 = 5 total attempts
  RETRY_BASE = 1.0 # seconds
  RETRY_CAP = 10.0 # seconds

  # Jittery sleep
  def self.retry_sleep(t)
    sleep Random.rand() * t
  end

  # Randomized exponential backoff with jitter
  #
  # @see https://www.awsarchitectureblog.com/2015/03/backoff.html
  def self.with_retry(*exceptions, attempts: RETRY_ATTEMPTS, base: RETRY_BASE, cap: RETRY_CAP, &block)
    attempt = 0

    begin
      return (yield)
    rescue *exceptions => error
      raise unless attempt < attempts

      warn "Retry #{block} on error: #{error}"

      retry_sleep [cap, base * 2 ** attempt].min

      attempt += 1

      retry
    end
  end
end
