#!/bin/bash
# Version = '20250829-154027'

set -e

if [ `hostname` != "fgcz-h-037" ]; then
	echo "******************************************************"
	echo "* PLEASE run this script on fgcz-h-037 *"
	echo "******************************************************"
	exit
fi

HOST=`hostname`

USER=`whoami`
ROOT_DIR=${USER:0:4}_test_new_sushi_`date +"%Y%m%d"`
SETUP_DIR='sushi_setup_script'
COMMON_SUSHI_DIR=/misc/fgcz01/sushi/new_SUSHI_2025
SKIP_UNIT_TESTS=false

for arg in "$@"; do
  case "$arg" in
    --skip-unit-tests)
      SKIP_UNIT_TESTS=true
      ;;
    --*)
      ;;
    *)
      if [ -z "$ROOT_DIR" ]; then
        ROOT_DIR="$arg"
      fi
      ;;
  esac
done


module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0

if [ `whoami` != "masaomi" ]; then
  git clone https://github.com/fgcz/new_SUSHI_2025 $ROOT_DIR
else
  git clone git@github.com:masaomi/new_SUSHI_2025 $ROOT_DIR
fi

cp -r $COMMON_SUSHI_DIR/docker_files $ROOT_DIR/
cd $ROOT_DIR/backend
bundle config set --local path 'vendor/bundle'
cp -r $COMMON_SUSHI_DIR/backend/vendor .
cp -r $COMMON_SUSHI_DIR/backend/db/csv_data db/
RAILS_ENV=development bundle exec rails db:create
RAILS_ENV=development bundle exec rails db:migrate
RAILS_ENV=development bundle exec rails runner db/import_from_csv.rb

if [ "$SKIP_UNIT_TESTS" = false ]; then
  if ! bundle exec rspec; then
    echo "WARNING"
    echo "Not all tests (Rails) passed and setup is NOT completed."
    echo "Please fixed the failure test(s) first."
    exit 1
  fi
fi


cd ../frontend
cp -r $COMMON_SUSHI_DIR/frontend/node_modules .

if [ "$SKIP_UNIT_TESTS" = false ]; then
  if ! npm test; then
    echo "WARNING"
    echo "Not all tests (Next.js) passed and setup is NOT completed."
    echo "Please fixed the failure test(s) first."
    exit 1
  fi
fi

echo
echo "*************************************"
echo "Conraturations! Setup is complete!"
echo "*************************************"
echo
echo "To start your test-new-SUSHI instance"
echo "1."
echo " $ cd $ROOT_DIR/"
echo "2."
echo " in case of skipping authentication (demo, course)"
echo " $ bash start-dev.sh"
echo ""
echo " in case of LDAP login (production)"
echo " $ bash start-dev.sh ENABLE_LDAP"
echo ""
echo " in case of using custom port numbers (backend: 4090, frontend: 4091)"
echo " $ bash start-dev.sh ENABLE_LDAP 4090 4091"
echo ""
echo "Note"
echo " * by default, it uses port numbers, 4050 (background), 4051 (frontend)"

