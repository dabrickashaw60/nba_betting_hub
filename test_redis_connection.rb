require 'redis'

begin
  redis = Redis.new(
    url: 
'redis://default:AWRPAAIjcDE2MjMxZjViZTMyMmQ0NWQ3YmE3Y2U5MmUwMDg2Nzk4NHAxMA@inviting-bunny-25679.upstash.io:6379',
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  )
  puts "Connected to Redis: #{redis.ping}" # Expect "PONG"
rescue => e
  puts "Failed to connect to Redis: #{e.message}"
end

