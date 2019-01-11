# $1 -> key in base 64
# $2 -> list of repositories comma separated with branch and submodule path (es: project1;develop:src,project2;master:src)

# Setup key for git

echo -e "$1" | base64 -d > ~/.ssh/id_rsa_myproject_ci
set -x
chmod 600 ~/.ssh/id_rsa_myproject_ci
echo -e "Host github.com\n User git\n IdentityFile ~/.ssh/id_rsa_myproject_ci\n StrictHostKeyChecking no" > ~/.ssh/config
chmod 600 ~/.ssh/config

repos="$(echo "$2" | tr ',' '\n')"

for repo in $repos ; do
  project=$(    echo "$repo" | tr ';' ' ' | awk '{ print $1 }')
  branch_path=$(echo "$repo" | tr ';' ' ' | awk '{ print $2 }')
  branch=$(     echo "$branch_path" | tr ':' ' ' | awk '{ print $1 }')
  path=$(       echo "$branch_path" | tr ':' ' ' | awk '{ print $2 }')

  git clone $project
  cd $(basename $project | tr '.' ' ' | awk '{ print $1 }')
  git checkout $branch
  git submodule update --init --recursive
  oldpwd=$PWD
  cd $path
  git fetch
  git checkout master
  cd $oldpwd
  git commit -a -m "auto commit for changing sources"
  sed -i 's/https:\/\/github.com\//git@github.com:/' .git/config
  git push origin $branch
done
