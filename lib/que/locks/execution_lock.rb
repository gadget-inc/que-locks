require "xxhash"

module Que
  SQL[:args_already_enqueued] = %{
    SELECT COUNT(*) FROM public.que_jobs WHERE args = $1 and finished_at IS NULL AND expired_at IS NULL;
  }

  SQL[:try_aquire_execution_lock] = %{
    SELECT pg_try_advisory_lock(42, $1) AS locked
  }

  SQL[:release_execution_lock] = %{
    SELECT pg_advisory_unlock(42, $1)
  }

  module Locks::ExecutionLock
    class << self
      def already_enqueued_job_wanting_lock?(args)
        args_string = Que.serialize_json(args)
        values = Que.execute(:args_already_enqueued, [args_string]).first
        values[:count] != 0
      end

      def can_aquire?(args)
        can_aquire_key?(lock_key(args))
      end

      def can_aquire_key?(key)
        result = false
        begin
          result = aquire!(key)
        ensure
          if result
            release!(key)
          end
        end
        result
      end

      def lock_key(args)
        XXhash.xxh32(Que.serialize_json(args), 42) / 2
      end

      def aquire!(key)
        result = Que.execute(:try_aquire_execution_lock, [key]).first
        result[:locked]
      end

      def release!(key)
        Que.execute(:release_execution_lock, [key])
      end
    end
  end
end
