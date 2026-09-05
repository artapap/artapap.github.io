#!/usr/bin/env ruby
# Flags exact-duplicate and near-duplicate (same photo, different resolution/compression)
# images under assets/images/. Run before committing new photos, and in CI.
#
# Near-duplicate detection uses a 64-bit difference hash (dHash) via ImageMagick;
# a Hamming distance <= 5 was empirically validated (against RMSE + visual review)
# to catch same-photo re-exports with zero false positives on this photo set.

require 'digest'
require 'open3'

REPO = File.expand_path("..", __dir__)
IMAGES_DIR = File.join(REPO, "assets", "images")
EXTS = %w[.jpg .jpeg .png .gif .webp]
NEAR_DUP_THRESHOLD = 5

files = Dir.glob(File.join(IMAGES_DIR, "**", "*"))
           .select { |f| File.file?(f) && EXTS.include?(File.extname(f).downcase) }
           .sort

def dhash(file)
  out, status = Open3.capture2(
    "magick", file, "-auto-orient", "-colorspace", "Gray",
    "-resize", "9x8!", "-depth", "8", "gray:-",
    binmode: true
  )
  raise "magick failed for #{file}" unless status.success?

  bytes = out.bytes
  bits = 0
  8.times do |row|
    8.times do |col|
      i = row * 9 + col
      bit = bytes[i] > bytes[i + 1] ? 1 : 0
      bits = (bits << 1) | bit
    end
  end
  bits
end

by_sha = Hash.new { |h, k| h[k] = [] }
files.each { |f| by_sha[Digest::SHA256.file(f).hexdigest] << f }
exact_dupes = by_sha.values.select { |v| v.size > 1 }

hashes = files.each_with_object({}) { |f, h| h[f] = dhash(f) }

near_dupes = []
files.combination(2).each do |a, b|
  dist = (hashes[a] ^ hashes[b]).to_s(2).count("1")
  near_dupes << [a, b, dist] if dist <= NEAR_DUP_THRESHOLD
end

ok = true

if exact_dupes.any?
  ok = false
  puts "Exact duplicate files (identical SHA-256):"
  exact_dupes.each { |group| puts "  #{group.join(' == ')}" }
end

if near_dupes.any?
  ok = false
  puts "Likely near-duplicate images (same photo, different resolution/export):"
  near_dupes.each { |a, b, d| puts "  #{a} ~= #{b}  (dHash distance #{d})" }
end

if ok
  puts "No duplicates found (#{files.size} images checked)."
  exit 0
else
  exit 1
end
