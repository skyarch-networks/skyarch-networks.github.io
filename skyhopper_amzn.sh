#!/bin/sh

#
# SkyHopper Install by Skyarchnetworks
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

function check_supported {
    local my_version=$(cat /etc/system-release)
    local supported=$(cat <<EOL
Amazon Linux AMI release 2015.03
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

# check version
echo "OSが動作確認バージョンか確認します"
check_supported

## yum update
echo "yum update及びreleasever固定を行います"
yum update -y >/dev/null
check_result $? "yum update"
sed  -e 's/.*\([0-9]\{4\}\.[0-9]\{2\}\)$/\1/' /etc/system-release > /etc/yum/vars/releasever
yum clean all

# gitをインストールしています
echo "gitをインストールしています"
yum install -y git
check_result $? "git インストール"

# Chefをインストールしています
echo "Chefをインストールしています"
curl -L https://www.chef.io/chef/install.sh | bash
check_result $? "Chef インストール"

# SkyHopperインストール用Cookbookを取得しています
echo "SkyHopperインストール用Cookbookを取得しています"

cd /usr/local/src
rm -rf /usr/local/src/skyhopper_cookbooks
git clone https://github.com/skyarch-networks/skyhopper_cookbooks.git
check_result $? "SkyHopper git clone"

tee /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper.json <<EOF >/dev/null
{
  "run_list": "recipe[skyhopper::default]"
}
EOF

# SkyHopper用初期設定を実行しています
echo "SkyHopperインストールChefを実行しています"
chef-client -z -j /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper.json
check_result $? "SkyHopper install Chef exec"

# MySQL ユーザーの作成
echo "MySQL を設定しています"

tee /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper_init.sql <<EOF >/dev/null
-- development
CREATE USER 'skyhopper_dev'@'localhost' IDENTIFIED BY 'hogehoge';
GRANT CREATE, SHOW DATABASES ON *.* TO 'skyhopper_dev'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`SkyHopperDevelopment\`.* TO 'skyhopper_dev'@'localhost';

-- production
SET storage_engine=INNODB;
CREATE USER 'skyhopper_prod'@'localhost' IDENTIFIED BY 'fugafuga';
CREATE DATABASE IF NOT EXISTS \`SkyHopperProduction\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`;
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`SkyHopperProduction\`.* TO 'skyhopper_prod'@'localhost';
EOF

mysql -u root -f /usr/local/src/skyhopper_cookbooks/cookbooks/skyhopper_init.sql
check_result $? "DB initialized"

# SkyHopper のセットアップ
cd skyhopper

# bundle install
echo "bundle install しています"
bundle install --quiet --path vendor/bundle > /dev/null 2>&1
check_result $? "bundle install"

# bower install
echo "bower install しています"
echo "n" | bower install -s > /dev/null 2>&1
check_result $? "bower install"

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
./scripts/skyhopper_daemon.sh start > /dev/null 2>&1
check_result $? "SkyHopper started"

# SkyHopper の初期設定
IP=`curl http://ifconfig.me`
echo "ブラウザから http://${IP} にアクセスし、SkyHopperの初期設定を行ってください"
echo "上記が終了後にEnterを押してください"
read TEST

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