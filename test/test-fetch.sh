#!/usr/bin/env bash

. "test/testlib.sh"

begin_test "fetch"
(
  set -e

  reponame="$(basename "$0" ".sh")"
  setup_remote_repo "$reponame"

  clone_repo "$reponame" clone

  clone_repo "$reponame" repo

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \*.dat" track.log

  contents="a"
  contents_oid=$(printf "$contents" | shasum -a 256 | cut -f 1 -d " ")

  printf "$contents" > a.dat
  git add a.dat
  git add .gitattributes
  git commit -m "add a.dat" 2>&1 | tee commit.log
  grep "master (root-commit)" commit.log
  grep "2 files changed" commit.log
  grep "create mode 100644 a.dat" commit.log
  grep "create mode 100644 .gitattributes" commit.log

  [ "a" = "$(cat a.dat)" ]

  assert_local_object "$contents_oid" 1

  refute_server_object "$reponame" "$contents_oid"

  git push origin master 2>&1 | tee push.log
  grep "(1 of 1 files)" push.log
  grep "master -> master" push.log

  assert_server_object "$reponame" "$contents_oid"

  # Add a file in a different branch
  git checkout -b newbranch
  b="b"
  b_oid=$(printf "$b" | shasum -a 256 | cut -f 1 -d " ")
  printf "$b" > b.dat
  git add b.dat
  git commit -m "add b.dat"
  assert_local_object "$b_oid" 1

  git push origin newbranch
  assert_server_object "$reponame" "$b_oid"

  # change to the clone's working directory
  cd ../clone

  git pull 2>&1 | grep "Downloading a.dat (1 B)"

  [ "a" = "$(cat a.dat)" ]

  assert_local_object "$contents_oid" 1


  # Remove the working directory and lfs files
  rm -rf .git/lfs/objects
  git lfs fetch 2>&1 | grep "(1 of 1 files)"
  assert_local_object "$contents_oid" 1

  # test with just remote specified
  rm -rf .git/lfs/objects
  git lfs fetch origin 2>&1 | grep "(1 of 1 files)"
  assert_local_object "$contents_oid" 1

  git checkout newbranch
  git checkout master
  rm -rf .git/lfs/objects

  git lfs fetch origin master newbranch
  assert_local_object "$contents_oid" 1
  assert_local_object "$b_oid" 1

  # Test include / exclude filters supplied in gitconfig
  rm -rf .git/lfs/objects
  git config "lfs.fetchinclude" "a*"
  git lfs fetch origin master newbranch
  assert_local_object "$contents_oid" 1
  refute_local_object "$b_oid"

  rm -rf .git/lfs/objects
  git config --unset "lfs.fetchinclude"
  git config "lfs.fetchexclude" "a*"
  git lfs fetch origin master newbranch
  refute_local_object "$contents_oid"
  assert_local_object "$b_oid" 1

  rm -rf .git/lfs/objects
  git config "lfs.fetchinclude" "a*,b*"
  git config "lfs.fetchexclude" "c*,d*"
  git lfs fetch origin master newbranch
  assert_local_object "$contents_oid" 1
  assert_local_object "$b_oid" 1

  rm -rf .git/lfs/objects
  git config "lfs.fetchinclude" "c*,d*"
  git config "lfs.fetchexclude" "a*,b*"
  git lfs fetch origin master newbranch
  refute_local_object "$contents_oid"
  refute_local_object "$b_oid"

  # Test include / exclude filters supplied on the command line
  git config --unset "lfs.fetchinclude"
  git config --unset "lfs.fetchexclude"
  rm -rf .git/lfs/objects
  git lfs fetch --include="a*" origin master newbranch
  assert_local_object "$contents_oid" 1
  refute_local_object "$b_oid"

  rm -rf .git/lfs/objects
  git lfs fetch --exclude="a*" origin master newbranch
  refute_local_object "$contents_oid"
  assert_local_object "$b_oid" 1

  rm -rf .git/lfs/objects
  git lfs fetch -I "a*,b*" -X "c*,d*" origin master newbranch
  assert_local_object "$contents_oid" 1
  assert_local_object "$b_oid" 1

  rm -rf .git/lfs/objects
  git lfs fetch --include="c*,d*" --exclude="a*,b*" origin master newbranch
  refute_local_object "$contents_oid"
  refute_local_object "$b_oid"
)
end_test

begin_test "fetch-recent"
(
  set -e

  reponame="fetch-recent"
  setup_remote_repo "$reponame"

  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \*.dat" track.log

  # generate content we'll use
  content0="filecontent0"
  content1="filecontent1"
  content2="filecontent2"
  content3="filecontent3"
  content4="filecontent4"
  content5="filecontent5"
  oid0=$(printf "$content0" | shasum -a 256 | cut -f 1 -d " ")
  oid1=$(printf "$content1" | shasum -a 256 | cut -f 1 -d " ")
  oid2=$(printf "$content2" | shasum -a 256 | cut -f 1 -d " ")
  oid3=$(printf "$content3" | shasum -a 256 | cut -f 1 -d " ")
  oid4=$(printf "$content4" | shasum -a 256 | cut -f 1 -d " ")
  oid5=$(printf "$content5" | shasum -a 256 | cut -f 1 -d " ")

  echo "[
  {
    \"CommitDate\":\"$(get_date -18d)\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content0}, \"Data\":\"$content0\"},
      {\"Filename\":\"file3.dat\",\"Size\":${#content5}, \"Data\":\"$content5\"}]
  },
  {
    \"CommitDate\":\"$(get_date -14d)\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content1}, \"Data\":\"$content1\"}]
  },
  {
    \"CommitDate\":\"$(get_date -5d)\",
    \"NewBranch\":\"other_branch\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content4}, \"Data\":\"$content4\"}]
  },
  {
    \"CommitDate\":\"$(get_date -1d)\",
    \"ParentBranches\":[\"master\"],
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content2}, \"Data\":\"$content2\"},
      {\"Filename\":\"file2.dat\",\"Size\":${#content3}, \"Data\":\"$content3\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin master
  git push origin other_branch
  assert_server_object "$reponame" "$oid0"
  assert_server_object "$reponame" "$oid1"
  assert_server_object "$reponame" "$oid2"
  assert_server_object "$reponame" "$oid3"
  assert_server_object "$reponame" "$oid4"

  rm -rf .git/lfs/objects

  git config lfs.fetchrecentalways false
  git config lfs.fetchrecentrefsdays 0
  git config lfs.fetchrecentremoterefs false
  git config lfs.fetchrecentcommitsdays 7

  # fetch normally, should just get the last state for file1/2
  git lfs fetch origin master
  assert_local_object "$oid2" "${#content2}"
  assert_local_object "$oid3" "${#content3}"
  assert_local_object "$oid5" "${#content5}"
  refute_local_object "$oid0"
  refute_local_object "$oid1"
  refute_local_object "$oid4"

  rm -rf .git/lfs/objects

  # now fetch recent - just commits for now
  git config lfs.fetchrecentrefsdays 0
  git config lfs.fetchrecentremoterefs false
  git config lfs.fetchrecentcommitsdays 7

  git lfs fetch --recent origin
  # that should have fetched master plus previous state needed within 7 days
  # current state
  assert_local_object "$oid2" "${#content2}"
  assert_local_object "$oid3" "${#content3}"
  # previous state is the 'before' state of any commits made in last 7 days
  # ie you can check out anything in last 7 days (may have non-LFS commits in between)
  assert_local_object "$oid1" "${#content1}"
  refute_local_object "$oid0"
  refute_local_object "$oid4"

  rm -rf .git/lfs/objects
  # now fetch other_branch as well
  git config lfs.fetchrecentrefsdays 6
  git config lfs.fetchrecentremoterefs false
  git config lfs.fetchrecentcommitsdays 7

  git lfs fetch --recent origin
  # that should have fetched master plus previous state needed within 7 days
  # current state PLUS refs within 6 days (& their commits within 7)
  assert_local_object "$oid2" "${#content2}"
  assert_local_object "$oid3" "${#content3}"
  assert_local_object "$oid1" "${#content1}"
  assert_local_object "$oid4" "${#content4}"
  # still omits oid0 since that's at best 13 days prior to other_branch tip
  refute_local_object "$oid0"

  # now test that a 14 day limit picks oid0 up from other_branch
  # because other_branch was itself 5 days ago, 5+14=19 day search limit
  git config lfs.fetchrecentcommitsdays 14

  git lfs fetch --recent origin
  assert_local_object "$oid0" "${#content0}"

  # push branch & test remote branch recent
  git push origin other_branch
  git branch -D other_branch

  rm -rf .git/lfs/objects
  git config lfs.fetchrecentcommitsdays 0
  git config lfs.fetchrecentremoterefs false
  git config lfs.fetchrecentrefsdays 6
  git lfs fetch --recent origin
  # should miss #4 until we include remote branches (#1 will always be missing commitdays=0)
  assert_local_object "$oid2" "${#content2}"
  assert_local_object "$oid3" "${#content3}"
  refute_local_object "$oid1"
  refute_local_object "$oid0"
  refute_local_object "$oid4"
  # pick up just snapshot at remote ref, ie #4
  git config lfs.fetchrecentremoterefs true
  git lfs fetch --recent origin
  assert_local_object "$oid4" "${#content4}"
  refute_local_object "$oid0"
  refute_local_object "$oid1"

)
end_test

begin_test "fetch-all"
(
  set -e

  reponame="fetch-all"
  setup_remote_repo "$reponame"

  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \*.dat" track.log

  NUMFILES=12
  # generate content we'll use
  for ((a=0; a < NUMFILES ; a++))
  do
    content[$a]="filecontent$a"
    oid[$a]=$(printf "${content[$a]}" | shasum -a 256 | cut -f 1 -d " ")
  done

  echo "[
  {
    \"CommitDate\":\"$(get_date -180d)\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content[0]}, \"Data\":\"${content[0]}\"},
      {\"Filename\":\"file2.dat\",\"Size\":${#content[1]}, \"Data\":\"${content[1]}\"}]
  },
  {
    \"NewBranch\":\"branch1\",
    \"CommitDate\":\"$(get_date -140d)\",
    \"Files\":[
      {\"Filename\":\"file3.dat\",\"Size\":${#content[2]}, \"Data\":\"${content[2]}\"}]
  },
  {
    \"ParentBranches\":[\"master\"],
    \"CommitDate\":\"$(get_date -100d)\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content[3]}, \"Data\":\"${content[3]}\"}]
  },
  {
    \"NewBranch\":\"remote_branch_only\",
    \"CommitDate\":\"$(get_date -80d)\",
    \"Files\":[
      {\"Filename\":\"file2.dat\",\"Size\":${#content[4]}, \"Data\":\"${content[4]}\"}]
  },
  {
    \"ParentBranches\":[\"master\"],
    \"CommitDate\":\"$(get_date -75d)\",
    \"Files\":[
      {\"Filename\":\"file4.dat\",\"Size\":${#content[5]}, \"Data\":\"${content[5]}\"}]
  },
  {
    \"NewBranch\":\"tag_only\",
    \"Tags\":[\"tag1\"],
    \"CommitDate\":\"$(get_date -70d)\",
    \"Files\":[
      {\"Filename\":\"file4.dat\",\"Size\":${#content[6]}, \"Data\":\"${content[6]}\"}]
  },
  {
    \"ParentBranches\":[\"master\"],
    \"CommitDate\":\"$(get_date -60d)\",
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content[7]}, \"Data\":\"${content[7]}\"}]
  },
  {
    \"NewBranch\":\"branch3\",
    \"CommitDate\":\"$(get_date -50d)\",
    \"Files\":[
      {\"Filename\":\"file4.dat\",\"Size\":${#content[8]}, \"Data\":\"${content[8]}\"}]
  },
  {
    \"CommitDate\":\"$(get_date -40d)\",
    \"ParentBranches\":[\"master\"],
    \"Files\":[
      {\"Filename\":\"file1.dat\",\"Size\":${#content[9]}, \"Data\":\"${content[9]}\"},
      {\"Filename\":\"file2.dat\",\"Size\":${#content[10]}, \"Data\":\"${content[10]}\"}]
  },
  {
    \"ParentBranches\":[\"master\"],
    \"CommitDate\":\"$(get_date -30d)\",
    \"Files\":[
      {\"Filename\":\"file4.dat\",\"Size\":${#content[11]}, \"Data\":\"${content[11]}\"}]
  }
  ]" | lfstest-testutils addcommits

  git push origin master
  git push origin branch1
  git push origin branch3
  git push origin remote_branch_only
  git push origin tag_only
  for ((a=0; a < NUMFILES ; a++))
  do
    assert_server_object "$reponame" "${oid[$a]}"
  done

  # delete remote_branch_only and make sure that objects are downloaded even
  # though not checked out to a local branch (full backup always)
  git branch -D remote_branch_only

  # delete tag_only to make sure objects are downloaded when only reachable from tag
  git branch -D tag_only

  rm -rf .git/lfs/objects

  git lfs fetch --all origin
  for ((a=0; a < NUMFILES ; a++))
  do
    assert_local_object "${oid[$a]}" "${#content[$a]}"
  done

)
end_test

begin_test "fetch: outside git repository"
(
  set +e
  git lfs fetch 2>&1 > fetch.log
  res=$?

  set -e
  if [ "$res" = "0" ]; then
    echo "Passes because $GIT_LFS_TEST_DIR is unset."
    exit 0
  fi
  [ "$res" = "128" ]
  grep "Not in a git repository" fetch.log
)
end_test
