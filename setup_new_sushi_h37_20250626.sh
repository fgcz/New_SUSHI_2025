#!/bin/bash
# Version = '20250704-162922'

set -e

if [ `hostname` != "fgcz-h-037" ] && [ `whoami` != "masaomi" ]; then
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

module load Dev/Ruby/3.3.7
module load Dev/node/22.16.0

if [ $# -eq 1 ]; then
  ROOT_DIR=$1
fi

git clone git@github.com:masaomi/new_SUSHI_2025 $ROOT_DIR
cd $ROOT_DIR/backend
bundle config set --local path 'vendor/bundle'
cp -r $COMMON_SUSHI_DIR/backend/vendor .
cp -r $COMMON_SUSHI_DIR/backend/db/csv_data db/
RAILS_ENV=development bundle exec rails db:create
RAILS_ENV=development bundle exec rails db:migrate
RAILS_ENV=development bundle exec rails runner db/import_from_csv.rb

bundle exec rspec

cd ../frontend
cp -r $COMMON_SUSHI_DIR/frontend/node_modules .

npm test

echo ""
echo "To start your test-new-SUSHI instance"
echo "1."
echo " $ cd $ROOT_DIR/backend"
echo " $ RAILS_ENV=development bundle exec rails s -b fgcz-h-037.fgcz-net.unizh.ch -p 4000"
echo "2."
echo " $ cd $ROOT_DIR/frontend"
echo " $ npm run dev -- --port 4001"
echo "3. start FGCZ VPN"
echo "4. access http://$HOST.fgcz-net.unizh.ch:4001"
echo ""
