#!/usr/bin/env ruby
# Caps every gallery image at MAX_EDGE px on its long edge and re-compresses it.
# This is the only resolution served on the site by design: there is no separate
# full-resolution original committed or served, to keep downloaded copies
# lower-quality. Run after adding new photos, before committing.

REPO = File.expand_path("..", __dir__)
IMAGES_DIR = File.join(REPO, "assets", "images")
MAX_EDGE = 1800
QUALITY = 70

Dir.glob(File.join(IMAGES_DIR, "*", "*")).sort.each do |path|
  next unless File.file?(path)

  dims = `identify -format "%w %h" "#{path}"`.strip.split.map(&:to_i)
  next if dims.size != 2

  width, height = dims
  next if [width, height].max <= MAX_EDGE

  system(
    "convert", path, "-auto-orient", "-resize", "#{MAX_EDGE}x#{MAX_EDGE}>",
    "-quality", QUALITY.to_s, path,
    exception: true
  )
  puts "optimized #{File.basename(File.dirname(path))}/#{File.basename(path)} (was #{width}x#{height})"
end
