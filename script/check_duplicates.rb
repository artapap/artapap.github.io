#!/usr/bin/env ruby
# Flags exact-duplicate and near-duplicate (same photo, different resolution/compression)
# images under assets/images/. Run before committing new photos, and in CI.
#
# Near-duplicate detection uses a 64-bit difference hash (dHash) via ImageMagick;
# a Hamming distance <= 5 was empirically validated (against RMSE + visual review)
# to catch same-photo re-exports with zero false positives on this photo set.
#
# Note: dHash values can differ by a bit or two between ImageMagick versions
# (e.g. local v7 vs a CI runner's v6) even for byte-identical input, since
# resize/grayscale math isn't guaranteed bit-identical across versions - hence
# the explicit "-filter Box" below, and the KNOWN_NOT_DUPES escape hatch for
# borderline pairs manually confirmed to be genuinely different photos.

require 'digest'
require 'open3'
require 'pathname'

REPO = File.expand_path("..", __dir__)
IMAGES_DIR = File.join(REPO, "assets", "images")
EXTS = %w[.jpg .jpeg .png .gif .webp]
NEAR_DUP_THRESHOLD = 5

# Pairs manually confirmed to be genuinely different photos, not duplicates,
# despite landing at/under the distance threshold (re-compression can nudge
# borderline dHash distances by a bit or two). Confirmed via visual review.
# Paths are relative to the repo root, so this works the same on any host.
KNOWN_NOT_DUPES = [
  %w[assets/images/home/60fa1a1b17.JPG assets/images/home/f4789f52db.JPG],
  %w[assets/images/early/bd9bc0c2d4.jpg assets/images/home/f4789f52db.JPG],
  %w[assets/images/volumes/51fdca0295.jpg assets/images/volumes/6b4bc160ac.jpeg],
  %w[assets/images/home/c4bc4bd94a.JPG assets/images/landscapes/3210c380b9.jpg],
].map(&:sort)

def rel(path)
  Pathname.new(path).relative_path_from(Pathname.new(REPO)).to_s
end

files = Dir.glob(File.join(IMAGES_DIR, "**", "*"))
           .select { |f| File.file?(f) && EXTS.include?(File.extname(f).downcase) }
           .sort

def dhash(file)
  out, status = Open3.capture2(
    "convert", file, "-auto-orient", "-colorspace", "Gray",
    "-filter", "Box", "-resize", "9x8!", "-depth", "8", "gray:-",
    binmode: true, err: File::NULL
  )
  raise "convert failed for #{file}" unless status.success?

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
  next if dist > NEAR_DUP_THRESHOLD
  next if KNOWN_NOT_DUPES.include?([rel(a), rel(b)].sort)

  near_dupes << [a, b, dist]
end

ok = true

if exact_dupes.any?
  ok = false
  puts "Exact duplicate files (identical SHA-256):"
  exact_dupes.each { |group| puts "  #{group.map { |f| rel(f) }.join(' == ')}" }
end

if near_dupes.any?
  ok = false
  puts "Likely near-duplicate images (same photo, different resolution/export):"
  near_dupes.each { |a, b, d| puts "  #{rel(a)} ~= #{rel(b)}  (dHash distance #{d})" }
end

if ok
  puts "No duplicates found (#{files.size} images checked)."
  exit 0
else
  exit 1
end
