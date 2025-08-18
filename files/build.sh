#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

set -e

# Cleanup function on failure
cleanup_on_failure() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "=== BUILD FAILED (exit code: $exit_code) ==="
        echo "Cleaning up /jenkins and /output directories..."
        # Move to root before cleanup
        cd /
        # Cleanup /jenkins directory
        if [ -d "/jenkins" ]; then
            echo "Cleaning /jenkins directory..."
            rm -rf /jenkins/*
            echo "/jenkins directory cleaned up."
        fi
        # Cleanup /output directory
        if [ -d "/output" ]; then
            echo "Cleaning /output directory..."
            rm -rf /output/*
            echo "/output directory cleaned up."
        fi
        echo "=== CLEANUP COMPLETED ==="
    fi
    exit $exit_code
}

# Set trap to cleanup on any error or exit
trap cleanup_on_failure ERR EXIT

if [[ $DISTRO == "debian" ]]; then
  locale-gen en_US.UTF-8
  update-locale
fi

# printenv

echo "Repo: $GIT_REPO"
echo "Tag: $GIT_TAG"
echo "PR ID: $PR_ID"
echo "ACS Branch: $ACS_BRANCH"
echo "Distro: $DISTRO"
echo "Flags: $FLAGS"

export ROOT=/jenkins
cd $ROOT
rm -fr deps/*jar deps/awsapi-lib deps/*.mar NONOSS

# Initialize git repository and fetch code
echo "Initializing git repository..."
if [ ! -d ".git" ]; then
    git init .
fi

# Add remote origin if it doesn't exist
if ! git remote get-url origin >/dev/null 2>&1; then
    echo "Adding remote origin: https://github.com/$GIT_REPO.git"
    git remote add origin "https://github.com/$GIT_REPO.git"
else
    echo "Setting remote origin URL: https://github.com/$GIT_REPO.git"
    git remote set-url origin "https://github.com/$GIT_REPO.git"
fi

# Fetch the repository
echo "Fetching repository from https://github.com/$GIT_REPO.git"
git reset --hard
git clean -fd
git fetch origin --depth=1 --progress

if [[ "${PR_ID}" != "" ]]; then
  # Find base branch
  BASE=$(curl https://api.github.com/repos/$GIT_REPO/pulls/$PR_ID | jq -r '.base.ref')
  git checkout ${BASE}
else
  # For regular branches/tags
  echo "Fetching and checking out: $ACS_BRANCH"
  if git ls-remote --heads origin "$ACS_BRANCH" | grep -q "$ACS_BRANCH"; then
      # It's a branch
      if [ "$(git rev-parse --abbrev-ref HEAD)" = "$ACS_BRANCH" ]; then
          echo "Already on branch $ACS_BRANCH, pulling latest changes with rebase..."
          git pull --rebase origin "$ACS_BRANCH"
      else
          git fetch origin "$ACS_BRANCH:$ACS_BRANCH" --depth=1 --progress
          git checkout "$ACS_BRANCH"
      fi
  elif git ls-remote --tags origin "$ACS_BRANCH" | grep -q "$ACS_BRANCH"; then
      # It's a tag
      git fetch origin "refs/tags/$ACS_BRANCH:refs/tags/$ACS_BRANCH" --depth=1 --progress
      git checkout "refs/tags/$ACS_BRANCH"
  else
      # Try to fetch as commit SHA
      git checkout "$ACS_BRANCH"
  fi
fi

# Add github remote
git remote add gh https://github.com/$GIT_REPO.git || true

# Apply PR
if [[ "${PR_ID}" != "" ]]; then
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"

  sed -i 's/^repoName=.*/repoName=cloudstack/g' tools/git/git-pr
  bash tools/git/git-pr $PR_ID --force
fi

export PATH="$HOME/.jenv/bin:$PATH"
if [[ $DISTRO == "centos6" ]]; then
  export PATH=/opt/rh/maven30/root/usr/bin:/opt/rh/rh-java-common/root/usr/bin:$PATH
fi

eval "$(jenv init -)"
echo $0
cat .java-version || true
jenv shell $(cat .java-version) || true
pwd
whoami
echo $PATH
java -version
javac -version
mvn -version

if [[ "${PR_ID}" != "" ]]; then
  export MINOR=shapeblue${PR_ID}
else
  export MINOR=1
fi

export VERSION=$(grep '<version>' pom.xml | head -2 | tail -1 | cut -d'>' -f2 |cut -d'<' -f1)
export BASE_VERSION=$(echo $VERSION | awk -F . '{print $1"."$2}')
export ACS_BUILD_OPTS="-Dnoredist -Dnonoss"
export MAVEN_OPTS="-Xmx4096m -XX:MaxPermSize=800m"

LIBS=NONOSS
if [ ! -d "$LIBS/.git" ]; then
  git clone https://github.com/shapeblue/cloudstack-nonoss.git $LIBS --depth=1 --progress
else
  cd $LIBS
  git pull origin main
  cd $ROOT
fi
cd $LIBS
bash -x install-non-oss.sh
cd $ROOT
cp $LIBS/vhd-util scripts/vm/hypervisor/xenserver/
chmod +x scripts/vm/hypervisor/xenserver/vhd-util

# Debian stuff
if [[ $DISTRO == "debian" ]]; then
  export ACS_BUILD_OPTS="-Dnoredist -Dnonoss $FLAGS"
  rm -frv ../cloudstack*deb
  rm -frv ../cloudstack*.tar.gz
  rm -frv ../cloudstack*.dsc
  rm -frv ../cloudstack*.changes

  echo "cloudstack (${VERSION}) unstable; urgency=low" > $ROOT/newchangelog
  echo "" >> $ROOT/newchangelog
  echo "  * Update the version to ${PACKAGE_VERSION}" >> $ROOT/newchangelog
  echo "" >> $ROOT/newchangelog
  echo " -- Apache CloudStack Dev <dev@cloudstack.apache.org>  $(date +'%a, %-d %b %Y %H:%m:%S +0530')" >> $ROOT/newchangelog
  echo "" >> $ROOT/newchangelog
  cat $ROOT/debian/changelog >> $ROOT/newchangelog
  mv $ROOT/newchangelog $ROOT/debian/changelog

  cd $ROOT

    dpkg-buildpackage -uc -us -b
  mv ../cloudstack-*.deb $ROOT
  for pkg in $(ls cloud*.deb);
  do
    cp $pkg /output
  done
else
  # Centos stuff
  cd $ROOT/packaging
  sed -i "s/DEFREL=.*$/DEFREL='-D_rel ${MINOR}'/g" package.sh

  case $DISTRO in
    el7)
      bash -x package.sh -p noredist -o rhel7 -d centos7 --release $MINOR
      ;;
    el8|el9)
      ln -sf /usr/bin/python2 /usr/bin/python
      bash -x package.sh -p noredist -o rhel8 -d centos8 --release $MINOR
      ;;
  esac

  cd $ROOT
  package_folder="dist/rpmbuild/RPMS/x86_64/"
  if [ ! -d $package_folder ];then
    package_folder="dist/rpmbuild/RPMS/noarch/"
  fi
  for pkg in $(ls $package_folder);
  do
    cp $package_folder/$pkg /output
  done
  for f in /etc/yum.repos.d/CentOS-*.repo; do
    [ -e "$f" ] || continue
    sed -i \
      -e 's|^mirrorlist=|#mirrorlist=|g' \
      -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' \
      "$f"
  done
  dnf install createrepo -y || true
  createrepo /output
fi

rm -rf $ROOT/*

# If we reach here, the build was successful
# Disable the cleanup trap for successful builds
trap - ERR EXIT

echo "=== BUILD COMPLETED SUCCESSFULLY ==="
echo "Packages available in /output directory"
