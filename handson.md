# CloudFormation

## 最小限のJSONでEC2インスタンスの作成

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "First Infra",
  "Resources": {
    "EC2Instance": {
      "Type": "AWS::EC2::Instance",
      "Properties": {
        "InstanceType": "t2.micro",
        "KeyName": "Hands-on",
        "ImageId": "ami-18869819"
      }
    }
  }
}
```

## パラメータを利用したEC2インスタンスの作成

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Simple Pattern (EC2x1)",
  "Parameters" : {
    "InstanceType" : {
      "Type" : "String",
      "Default" : "t2.micro",
      "AllowedValues" : ["t2.micro", "t2.small"],
      "Description" : "Choose instance type."
    }
  },
  "Resources": {
    "EC2Instance": {
      "Type": "AWS::EC2::Instance",
      "Properties": {
        "InstanceType": {
          "Ref": "InstanceType"
        },
        "KeyName": "Hands-on",
        "ImageId": "ami-18869819"
      }
    }
  }
}
```

### EBSサイズ指定方法

```json
"BlockDeviceMappings": [
  {
    "DeviceName": "/dev/xvda",
    "Ebs": {
          "VolumeSize": "20",
          "VolumeType": "gp2"
    }
  }
]
```

### セキュリティグループの指定

```json
{
  "AWSTemplateFormatVersion": "2010-09-09",
  "Description": "Simple Pattern (EC2x1)",
  "Resources": {
    "EC2Instance": {
      "Type": "AWS::EC2::Instance",
      "Properties": {
        "InstanceType": "t2.micro",
        "KeyName": "Hands-on",
        "ImageId": "ami-18869819",
        "SecurityGroupIds": [
          {
            "Ref": "MySecurityGroup"
          }
        ]
      }
    },
    "MySecurityGroup": {
      "Type": "AWS::EC2::SecurityGroup",
      "Properties": {
        "GroupDescription": "Enable Web access All Location",
        "SecurityGroupIngress": [
          {
            "CidrIp" : "0.0.0.0/0",
            "FromPort" : 80,
            "IpProtocol" : "tcp",
            "ToPort" : 80
          },
          {
            "CidrIp" : "0.0.0.0/0",
            "FromPort" : 443,
            "IpProtocol" : "tcp",
            "ToPort" : 443
          }
        ]
      }
    }
  }
}
```

# Chef

## hello_world Cookbookの作成

### hello_world ファイルの作成

```bash
echo 'Hello World' > files/default/hello_world
```

### default.rb
```ruby
cookbook_file "hello_world" do
  path "/tmp/hello_world"
  action :create_if_missing
end
```

### runlist
```json
{
  "run_list": [
    "recipe[hello_world::default]"
  ]
}
```

## パッケージのインストール

### default.rb

```ruby
package [ "httpd", "php" ] do
  action :install
end
```

### サービスの自動起動設定

```ruby
service サービス名 do
  action [:enable, :start]
end
```

# Serverspec

## インストール

```bash
# gem install serverspec rake --no-ri --no-rdoc
```

## 自分でテストを作成する

```ruby
require 'spec_helper'

describe user('devops') do
  it { should exist }
  it { should belong_to_group 'devops' }
end

describe package('httpd') do
  it { should be_installed }
end
```

## コマンド実行リソース

```ruby
describe command('実行するコマンド') do
  its(:stdout) { should match /正規表現パターン/ }
end
```

## AmazonLinuxで現在のインスタンスサイズを取得

```bash
# curl http://169.254.169.254/latest/meta-data/instance-type
```

## デフォルトで利用できるリソース
http://serverspec.org/resource_types.html

# Zabbix

## gemのインストール

```bash
# gem install sky_zabbix --version '~> 2.2.0'
```

## 確認

```bash
# gem list
```

## APIを叩いてバージョン確認

```bash
# curl -d '{"jsonrpc":"2.0","method":"apiinfo.version","id":1,"auth":null,"params":{}}' -H "Content-Type: application/json-rpc" http://ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com/zabbix/api_jsonrpc.php
```

## API経由でホストを作成するコード

```ruby
# (1)ライブラリの宣言
require 'sky_zabbix'

# (2)Zabbix APIのURLの宣言
zabbix_url  = 'http://ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com/zabbix/api_jsonrpc.php'
# (3)Zabbixにログインするためのユーザー名とパスワードの宣言
zabbix_user = 'admin'
zabbix_pass = 'ilikerandompasswords'

# (4)SkyZabbixクライアントの生成
client = SkyZabbix::Client.new(zabbix_url)
# (5)認証
client.login(zabbix_user, zabbix_pass)

# (6)リクエストを送信
puts client.host.create(
  host: "UserXXServer2", # ホスト名
  interfaces: [{
    type: 1, # エージェントのインターフェース
    main: 1, #　標準
    ip: "監視対象サーバIP", # ZabbbixエージェントのIPアドレス
    dns: "",
    port: 10050, # Zabbbixエージェントのポート番号
    useip: 1 # 接続方法、ここでは「IPアドレス」を指定
  }],
  groups: [
    groupid: "2", # グループID、ここでは「Linux Servers」を指定
  ]
)
```

## API経由でアイテムを作成するコード

```ruby
require 'sky_zabbix'

zabbix_url  = 'http://ec2-xx-xx-xx-xx.ap-northeast-1.compute.amazonaws.com/zabbix/api_jsonrpc.php'
zabbix_user = 'admin'
zabbix_pass = 'ilikerandompasswords'

client = SkyZabbix::Client.new(zabbix_url)
client.login(zabbix_user, zabbix_pass)

# (1)リクエストを送信
puts result = client.hostinterface.get(
  output: "extend", # オブジェクトのプロパティを返す
  hostids: "101xx" # ホストID、先ほど作成したホストのIDを指定
)

# (2)インターフェースIDを代入
interface_id = result[0]['interfaceid']

# (3)リクエストを送信
puts client.item.create(
  name: "CPU_Load_Average", # 名前
  key_: "system.cpu.load[all,avg1]", # キー
  hostid: "101xx", # ホストID、先ほど作成したホストのIDを指定
  type: 0, # タイプ、ここではZabbix agentを指定
  value_type: 0, # データ型、ここでは数値（浮動小数）を指定
  interfaceid: interface_id, # インターフェースID
  delay: 30 # 更新間隔
)
```
