#!/usr/bin/env bash
# Downloads the app's photos from Pexels (Pexels License: free for
# commercial use, no attribution required). Run from the repo root:
#   bash tool/fetch_photos.sh
# Each photo is listed with its page in docs/release/PHOTO_CREDITS.md.
set -euo pipefail
cd "$(dirname "$0")/.."

get() { # <pexels id> <output path>
  local url="https://images.pexels.com/photos/$1/pexels-photo-$1.jpeg?auto=compress&cs=tinysrgb&w=1080"
  curl -fsSL "$url" -o "$2" && echo "ok   $2" || echo "FAIL $2 ($1)"
}

M=assets/images/moves
get 23224743 $M/march.jpg
get 4498280  $M/arm_circles.jpg
get 6339454  $M/shoulder_rolls.jpg
get 7592371  $M/hip_circles.jpg
get 7187820  $M/leg_swings.jpg
get 7663227  $M/cat_cow.jpg
get 5036902  $M/wall_pushup.jpg
get 8899512  $M/chair_squat.jpg
get 8032754  $M/squat.jpg
get 4534643  $M/glute_bridge.jpg
get 40139104 $M/static_lunge.jpg
get 7880277  $M/step_up.jpg
get 4853085  $M/step_jacks.jpg
get 7801495  $M/plank_knees.jpg
get 5149167  $M/plank.jpg
get 6454196  $M/bird_dog.jpg
get 8038626  $M/dead_bug.jpg
get 3758142  $M/hamstring_stretch.jpg
get 6455768  $M/quad_stretch.jpg
get 3822147  $M/child_pose.jpg
get 3768179  $M/legs_up_wall.jpg
get 7351724  $M/box_breathing.jpg

P=assets/images/photos
get 35008222 $P/food.jpg
get 6940881  $P/sleep.jpg
echo "Done."
