# frozen_string_literal: true

module VisionHub
  DEFAULT_APPLICATION_ID = "tobiasz-p.vision-hub"
end

# Umbrella require for the VisionHub daemon library. The daemon and the spec
# suite both go through this entry point.
require_relative "vision_hub/runtime_dir"
require_relative "vision_hub/camera"
require_relative "vision_hub/config"
require_relative "vision_hub/secret_store"
require_relative "vision_hub/clock"
require_relative "vision_hub/health_probe"
require_relative "vision_hub/child_process"
require_relative "vision_hub/frame_pump"
require_relative "vision_hub/supervisor"
require_relative "vision_hub/ipc"
