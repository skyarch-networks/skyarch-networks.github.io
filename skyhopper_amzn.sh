#!/bin/sh

#
# SkyHopper one-liner installer by Skyarchnetworks
#

## CommonFunction
function check_result {
    local result=$1
    local point=$2

    if [ "${result}" -eq 0 ]; then
        echo -e "\033[0;32m ${point} Success \033[0;39m"
    else
        echo -e "\033[0;31m ${point} Failed \033[0;39m"
        exit 1
    fi
}

function check_exec_user {
    local uid=$(id | sed 's/uid=\([0-9]*\)(.*/\1/')
    if [ $uid -ne 500 ]; then
        check_result 1 "Check exec user (exec with ec2-user please)"
    else
        check_result 0 "Check exec user"
    fi
}

function check_supported {
    local my_version=$(cat /etc/system-release)
    local supported=$(cat <<EOL
Amazon Linux AMI release 2015.03
Amazon Linux AMI release 2015.09
EOL
    )

    orgIFS=$IFS
    IFS=$'\n'
    local flg=1
    for support_version in ${supported}; do
        if [ "${my_version}" = "${support_version}" ]; then
            flg=0
        fi
    done
    IFS=$orgIFS

    if [ "${flg}" -ne 0 ]; then
        check_result 1 "${my_version} is Not Supported Version"
        exit 1
    else
        check_result 0 "${my_version} is Supported Version"
    fi
}

# #####
# MAIN
# #####

# check user
echo "実行ユーザをチェックします"
check_exec_user

# check version
echo "OSが動作確認バージョンか確認します"
check_supported

## yum update
echo "yum update及びreleasever固定を行います"
sudo yum update -y >/dev/null
check_result $? "yum update"
sudo sh -c "sed -e 's/.*\([0-9]\{4\}\.[0-9]\{2\}\)$/\1/' /etc/system-release > /etc/yum/vars/releasever"
check_result $? "releasever固定"
sudo yum clean all

# gitをインストールしています
echo "gitをインストールしています"
sudo yum install -y git
check_result $? "git インストール"

# Chefをインストールしています
echo "Chefをインストールしています"
curl -L https://www.chef.io/chef/install.sh | sudo bash
check_result $? "Chef インストール"

# SkyHopperインストール用Cookbookを取得しています
echo "SkyHopperインストール用Cookbookを取得しています"

cd /usr/local/src
sudo rm -rf /usr/local/src/skyhopper_cookbooks
sudo git clone https://github.com/skyarch-networks/skyhopper_cookbooks.git
check_result $? "SkyHopper git clone"

sudo tee /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper.json <<EOF >/dev/null
{
  "run_list": "recipe[skyhopper::default]"
}
EOF

# SkyHopper用初期設定を実行しています
echo "SkyHopperインストールChefを実行しています"
cd /usr/local/src/skyhopper_cookbooks/cookbooks
sudo chef-client -z -j skyhopper.json
check_result $? "SkyHopper install Chef exec"

# MySQL ユーザーの作成
echo -e "\033[0;31m ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい \033[0;39m"
echo "MySQL ユーザを作成しています"

sudo tee /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper_init.sql <<EOF >/dev/null
-- development
GRANT USAGE ON *.* TO 'skyhopper_dev'@'localhost';
DROP USER 'skyhopper_dev'@'localhost';
CREATE USER 'skyhopper_dev'@'localhost' IDENTIFIED BY 'hogehoge';
GRANT CREATE, SHOW DATABASES ON *.* TO 'skyhopper_dev'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`SkyHopperDevelopment\`.* TO 'skyhopper_dev'@'localhost';

-- production
SET storage_engine=INNODB;
GRANT USAGE ON *.* TO 'skyhopper_prod'@'localhost';
DROP USER 'skyhopper_prod'@'localhost';
CREATE USER 'skyhopper_prod'@'localhost' IDENTIFIED BY 'fugafuga';
CREATE DATABASE IF NOT EXISTS \`SkyHopperProduction\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`SkyHopperProduction\`.* TO 'skyhopper_prod'@'localhost';

flush privileges;
EOF

mysql -u root < /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper_init.sql
check_result $? "DB initialized"
echo -e "\033[0;31m ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい ※本番環境ではMySQLユーザ設定をこのまま利用しないで下さい \033[0;39m"

# SkyHopper のセットアップ
cd ~/skyhopper

# bundle install
echo "bundle install しています"
bundle install --quiet --path vendor/bundle > /dev/null 2>&1
check_result $? "bundle install"

# bower install
echo "bower install しています"
bower install -s > /dev/null 2>&1
check_result $? "bower install"

# TypeScriptコンパイル
echo "TypeScriptをコンパイルしています"
sudo npm i -g gulp > /dev/null 2>&1
check_result $? "gulp install"
cd frontend/
npm i > /dev/null 2>&1
check_result $? "npm init"
gulp tsd > /dev/null 2>&1
check_result $? "gulp tsd"
gulp ts > /dev/null 2>&1
check_result $? "gulp ts"
cd ../../skyhopper/

# database.yml
echo "database.yml を設定しています"
cp config/database_default.yml config/database.yml
check_result $? "cp and setting database.yml"

# database.yml修正
# development
# username: root -> username: skyhopper_dev
sed -i -e "16s/root/skyhopper_dev/g" config/database.yml

# password: -> password: 'hogehoge'
sed -i -e "17s/:/: 'hogehoge'/g" config/database.yml

# production
# username: SkyHopper -> username: skyhopper_prod
sed -i -e "68s/SkyHopper/skyhopper_prod/g" config/database.yml

# password: <%= ENV['SKYHOPPER_DATABASE_PASSWORD'] %> -> password: 'fugafuga'
sed -i -e "69s/password.*/password: 'fugafuga'/g" config/database.yml

# DB のセットアップ
# データベースの作成
echo "データベース を作成しています"
bundle exec rake db:create > /dev/null 2>&1
check_result $? "DB created"

# マイグレーション
echo "データベース をマイグレーションしています"
# development
bundle exec rake db:migrate > /dev/null 2>&1
check_result $? "DB migrated development"

# production
bundle exec rake db:migrate RAILS_ENV=production > /dev/null 2>&1
check_result $? "DB migrated production"

# 初期データの挿入
echo "初期データ を作成しています"
# development
bundle exec rake db:seed > /dev/null 2>&1
check_result $? "DB seed development"

# production
bundle exec rake db:seed RAILS_ENV=production > /dev/null 2>&1
check_result $? "DB seed production"

# 起動
echo "サービス を起動しています"
if [ ! -d ./tmp/pids ]; then
  mkdir ./tmp/pids
fi
./scripts/skyhopper_daemon.sh start > /dev/null 2>&1
echo "起動まで 1分間待ちます"
sleep 180
check_result $? "SkyHopper (maybe) started"

# SkyHopper の初期設定
IP=$(curl --silent http://169.254.169.254/latest/meta-data/public-ipv4)
echo "ブラウザから http://${IP} にアクセスし、SkyHopperの初期設定を行ってください"
echo "上記が終了後にEnterを押してください"
read -s -n 1 TEST < /dev/tty

# Chef Server の鍵を設置
echo "鍵 を作成しています"
cp -r ~/skyhopper/tmp/chef ~/.chef > /dev/null 2>&1
check_result $? "Chef key created"

# SkyHopper の再起動
echo "サービス を再起動しています"
./scripts/skyhopper_daemon.sh stop > /dev/null 2>&1
check_result $? "SkyHopper stoped"
./scripts/skyhopper_daemon.sh start
check_result $? "SkyHopper started"

echo "完了しました"
