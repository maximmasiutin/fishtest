#!/bin/bash


# --min_threads Fishtest option
MINTHREADS=1

# Read credentials from Windows registry (HKCU\SOFTWARE\Fishtest)
read_registry() {
    local name="$1"
    powershell.exe -NoProfile -Command "Get-ItemProperty -Path 'HKCU:\SOFTWARE\Fishtest' -Name '$name' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty '$name'" 2>/dev/null | tr -d '\r\n'
}

FISHTEST_USERNAME=$(read_registry "FISHTEST_USERNAME")
FISHTEST_PASSWORD=$(read_registry "FISHTEST_PASSWORD")
FISHTEST_GITHUB_TOKEN=$(read_registry "FISHTEST_GITHUB_TOKEN")

if [ -z "$FISHTEST_USERNAME" ] || [ -z "$FISHTEST_PASSWORD" ] || [ -z "$FISHTEST_GITHUB_TOKEN" ]; then
    echo "Error: Could not read credentials from registry HKCU\\SOFTWARE\\Fishtest"
    echo "Required values: FISHTEST_USERNAME, FISHTEST_PASSWORD, FISHTEST_GITHUB_TOKEN"
    exit 1
fi

# GitHub token for API rate limiting (5000 calls/hour instead of 60)
export GITHUB_TOKEN="$FISHTEST_GITHUB_TOKEN"

# Create .netrc for requests library (fishtest uses this for GitHub API auth)
cat > ~/.netrc << EOF
machine api.github.com
login $FISHTEST_USERNAME
password ${GITHUB_TOKEN}

machine raw.githubusercontent.com
login $FISHTEST_USERNAME
password ${GITHUB_TOKEN}
EOF
chmod 600 ~/.netrc

# Check if current directory is "worker"
if [ "$(basename "$PWD")" != "worker" ]; then
    echo "Error: Must run this script from the 'worker' directory"
    exit 1
fi

[ -f fish.exit ] && rm fish.exit

while true; do

  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' update
  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade
  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade
  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' autoremove
  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' clean
  sudo DEBIAN_FRONTEND='noninteractive' apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' autoremove

  export CXXFLAGS="-O3 -march=native -mtune=native"
  export CFLAGS="-O3 -march=native -mtune=native"
  export CPPFLAGS="-O3 -march=native -mtune=native"

  chmod +x worker.py

  export ARCH=x86-64-avx512icl
  nice -n 19 python ./worker.py --protocol http --concurrency MAX --max_memory MAX --min_threads $MINTHREADS
  status=$?

  if [ $status -ne 0 ]; then
    echo "worker.py exited with code $status, stopping loop."
    exit $status
  fi

  echo "worker.py exited cleanly, restarting..."
  rm -f fish.exit
done
