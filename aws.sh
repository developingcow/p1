# create vpc
vpc=$(aws ec2 create-vpc --region us-east-1 --cidr-block 10.0.0.0/24 \
    --tag-specification 'ResourceType=vpc,Tags=[{Key=project,Value=wecloud}]')
vpc_id=$(echo $vpc | jq -r .Vpc.VpcId)
aws ec2 wait vpc-available --vpc-ids $vpc_id
echo vpc created: $vpc_id

# tag default route table
default_rt_id=$(
    aws ec2 describe-route-tables --filters \
        "Name=association.main,Values=true" \
        --query "RouteTables[*].RouteTableId" --output text
)
aws ec2 create-tags --resources $default_rt_id --tags Key=project,Value=wecloud

# create internet gateway
igw=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=project,Value=wecloud}]')
igw_id=$(echo $igw | jq -r .InternetGateway.InternetGatewayId)
aws ec2 wait internet-gateway-exists --internet-gateway-id $igw_id
echo igw created: $igw_id

# attach igw to vpc
aws ec2 attach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id

# create subnet
subnet=$(aws ec2 create-subnet --cidr-block 10.0.0.0/25 --vpc-id $vpc_id \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=project,Value=wecloud}]')
subnet_id=$(echo $subnet | jq -r .Subnet.SubnetId)
aws ec2 wait subnet-available --subnet-id $subnet_id
echo subnet created: $subnet_id

aws ec2 modify-subnet-attribute --subnet-id $subnet_id --map-public-ip-on-launch

# create route table
rtb=$(aws ec2 create-route-table --vpc-id $vpc_id \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=project,Value=wecloud}]')
rtb_id=$(echo $rtb | jq -r .RouteTable.RouteTableId)
echo route table created: $rtb_id

# associate route table with subnet
rt_subnet_association=$(aws ec2 associate-route-table --route-table-id $rtb_id --subnet-id $subnet_id)

# setting up route to access igw
rt_igw_route=$(aws ec2 create-route --route-table-id $rtb_id --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id)

# setup security group that allows tcp from anywhere
sg=$(aws ec2 create-security-group --group-name allow-ssh --description "Allow SSH" --vpc-id $vpc_id \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=project,Value=wecloud}]')
sg_id=$(echo $sg | jq -r .GroupId)
sg_rule=$(aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol tcp --port 22 --cidr 0.0.0.0/0)
sg_rule=$(aws ec2 authorize-security-group-ingress --group-id $sg_id --protocol all --source-group $sg_id) # allow traffic within sg

# setting up ec2 instances
master=$(
    aws ec2 run-instances --image-id ami-06aa3f7caf3a30282 --instance-type t2.small \
        --user-data file://user-data.sh \
        --security-group-id $sg_id \
        --key-name ssh \
        --subnet-id $subnet_id \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=master-node-01},{Key=project,Value=wecloud}]'
)

worker1=$(
    aws ec2 run-instances --image-id ami-06aa3f7caf3a30282 --instance-type t2.micro \
        --user-data file://user-data.sh \
        --security-group-id $sg_id \
        --key-name ssh \
        --subnet-id $subnet_id \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=worker-node-01},{Key=project,Value=wecloud}]'
)

worker2=$(
    aws ec2 run-instances --image-id ami-06aa3f7caf3a30282 --instance-type t2.micro \
        --user-data file://user-data.sh \
        --security-group-id $sg_id \
        --key-name ssh \
        --subnet-id $subnet_id \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=worker-node-02},{Key=project,Value=wecloud}]'
)
