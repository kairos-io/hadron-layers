#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/usr/bin"
printf 'git executable\n' > "$test_dir/usr/bin/git"
chmod 0755 "$test_dir/usr/bin/git"
ln "$test_dir/usr/bin/git" "$test_dir/usr/bin/git-receive-pack"

before_git=$(stat -c '%i' "$test_dir/usr/bin/git")
before_receive=$(stat -c '%i' "$test_dir/usr/bin/git-receive-pack")
[[ "$before_git" == "$before_receive" ]]

"$script_dir/materialize-hardlinks.sh" "$test_dir"

after_git=$(stat -c '%i' "$test_dir/usr/bin/git")
after_receive=$(stat -c '%i' "$test_dir/usr/bin/git-receive-pack")
[[ "$after_git" != "$after_receive" ]]
[[ $(cat "$test_dir/usr/bin/git") == 'git executable' ]]
[[ $(cat "$test_dir/usr/bin/git-receive-pack") == 'git executable' ]]
[[ $(stat -c '%a' "$test_dir/usr/bin/git") == 755 ]]
[[ $(stat -c '%a' "$test_dir/usr/bin/git-receive-pack") == 755 ]]

echo 'materialize-hardlinks tests passed'
