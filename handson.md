# CloudFormation

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

# 
