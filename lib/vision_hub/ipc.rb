# frozen_string_literal: true

require 'json'

module VisionHub
  # Line-delimited JSON framing for the daemon's stdin/stdout protocol.
  #
  # The reader is incremental and defensive: messages may arrive split across
  # arbitrary chunk boundaries, several per read, or not at all. Anything that
  # cannot possibly be a well-formed message is dropped and reported as a
  # structured problem rather than crashing the event loop.
  class Ipc
    # A single JSON line above this size is treated as hostile: dropped, with
    # everything up to its newline discarded.
    MAX_LINE_BYTES = 64 * 1024

    def self.encode(payload)
      "#{JSON.generate(payload)}\n"
    end

    class Reader
      Result = Struct.new(:kind, :message, :detail, keyword_init: true)

      def initialize(max_line_bytes: MAX_LINE_BYTES)
        @max_line_bytes = max_line_bytes
        @buffer = +''
        @discarding = false
      end

      # Feed raw bytes; returns zero or more results. Kinds:
      #   :message   - parsed Hash in #message
      #   :oversize  - a line exceeded MAX_LINE_BYTES and was dropped
      #   :invalid   - non-empty line that was not a JSON object
      # Empty lines are skipped silently.
      def feed(chunk)
        @buffer << chunk
        results = []
        while (newline_at = @buffer.index("\n"))
          line = slice_line(newline_at)
          next if line.strip.empty?

          if @discarding || line.bytesize > @max_line_bytes
            was_discarding = @discarding
            @discarding = false
            # A runaway line already reported on cap is silent until its end.
            unless was_discarding
              detail = "line exceeds #{@max_line_bytes} bytes"
              results << Result.new(kind: :oversize, detail:)
            end
          elsif (message = parse_object(line))
            results << Result.new(kind: :message, message: message)
          else
            results << Result.new(kind: :invalid, detail: truncate(line))
          end
        end
        drop_runaway_buffer(results)
        results
      end

      private

      def slice_line(newline_at)
        line = @buffer.slice!(0..newline_at)
        line.chomp
      end

      def parse_object(line)
        message = JSON.parse(line)
        message if message.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def truncate(line)
        line.byteslice(0, 200)
      end

      # A pathological producer may stream bytes with no newline forever. Cap
      # the buffer; when it eventually ends, report one oversize result.
      def drop_runaway_buffer(results)
        return unless @buffer.bytesize > @max_line_bytes

        @discarding = true
        @buffer.clear
        results << Result.new(kind: :oversize, detail: "runaway line exceeds #{@max_line_bytes} bytes")
      end
    end
  end
end
