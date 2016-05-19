#!/bin/sh -xe

#  nwjs-cherry-pick.sh
#  
#
#  Created by Jefry on 12/5/16.
#

if [ $# -eq 0 ]; then
  echo "please specify remote_branch"
  exit 1;
fi

## find remote
REMOTES=$(git remote)
REMOTE=""
REMOTE_COUNT=0
for remote in $REMOTES
do
  if [ $remote != "origin" ]; then
    REMOTE=$remote
  fi
  let REMOTE_COUNT=REMOTE_COUNT+1
done

if [ $REMOTE_COUNT -eq 2 ] && [ $remote != "" ]; then
  echo "using remote "$REMOTE
else
  if [ $# -le 1 ]; then
    echo "please specify remote"
    exit 1;
  else
    REMOTE=$2
  fi
  echo "using remote "$REMOTE
fi

CUR_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "current  branch "$CUR_BRANCH

TEMP_BRANCH=$CUR_BRANCH"-bot"
echo "temp     branch "$TEMP_BRANCH

#check if temp branch exist
BRANCHES=$(git branch | cut -c 3-)
for branch in $BRANCHES
do
  if [ $branch == $TEMP_BRANCH ]; then
    echo $TEMP_BRANCH already exist please delete / rename
    exit 1
  fi
done

BASE_COMMIT=$1
echo "fetching "$BASE_COMMIT
git fetch $BASE_COMMIT:$TEMP_BRANCH

#check if remote has not diverge from current
#if [ $(git merge-base $CUR_BRANCH $TEMP_BRANCH) == $(git log --pretty=format:"%H" -n 1 $TEMP_BRANCH) ]; then
#  echo cherry-pick unnecessary
#  exit 0
#fi

#update current branch
echo "fetch + pull origin/"$CUR_BRANCH
git fetch origin +refs/heads/$CUR_BRANCH:refs/remotes/origin/$CUR_BRANCH
git pull origin $CUR_BRANCH

#find last commit for cherry-pick
SKIP=0
while [ $(git log --pretty=format:"%ae" --skip=$SKIP -1) == "jefry.ted@vcube.co.jp" ]; do
    let SKIP=SKIP+1
done
LAST_PICK=$(git log --pretty=format:"%h" --skip=$SKIP -1)

CHERRY_PICK=$(git log HEAD...$LAST_PICK --pretty=format:"%h" --reverse)
echo "cherry pick "$CHERRY_PICK

git checkout $TEMP_BRANCH
#git branch -u origin/$CUR_BRANCH #set tracking
if ! git cherry-pick $CHERRY_PICK; then
  git mergetool
  echo "please run git cherry-pick --continue manually"
  exit 1
fi
