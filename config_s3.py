#!/usr/bin/python3

import argparse
import boto3
import os

from purity_fb import PurityFb, ObjectStoreAccessKey, rest

# Disable warnings.
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--account", default='datateam', help="Service account name.")
    parser.add_argument("--user", default='spark', help="Account user name.")
    parser.add_argument("--outfile", default='spark-defaults.conf',
                        help="Output Spark conf file.")
    args = parser.parse_args()

    # Create PurityFb object for a certain array using environment variables.
    FB_MGMT = os.environ.get('FB_MGMT_VIP')
    TOKEN = os.environ.get('FB_MGMT_TOKEN')

    if not FB_MGMT or not TOKEN:
        print("Requires environment variables for logging into FlashBlade REST: please set FB_MGMT_VIP and FB_MGMT_TOKEN")
        exit(1)

    fb = PurityFb(FB_MGMT)
    fb.disable_verify_ssl()

    # Step 0: login to the FlashBlade management API
    try:
        fb.login(TOKEN)
    except rest.ApiException as e:
        print("Exception: %s\n" % e)
        exit()

    # Step 1: Create service account
    try:
        res = fb.object_store_accounts.create_object_store_accounts(names=[args.account])
        print("Creating service account {}".format(args.account))
    except:
        print("Service account {} already exists".format(args.account))

    # Step 2: Create user account
    accountuser = args.account + '/' + args.user

    try:
        # post the object store user object myobjuser on the array
        print("Creating user account {}".format(accountuser))
        res = fb.object_store_users.create_object_store_users(names=[accountuser])
    except:
        print("User {} already exists".format(accountuser))

    # Step 3: Create access keys

    res = fb.object_store_access_keys.list_object_store_access_keys(filter="user.name=\'{}\'".format(accountuser))
    if len(res.items) == 2:
        print("User {} cannot create more access keys.".format(accountuser))
        exit(1)

    # generate access key and secret key for object store user
    # note: you need to handle the secret key since you can't retrieve it from the array after create
    accesskey=""
    secretkey=""
    try:
        res = fb.object_store_access_keys.create_object_store_access_keys(
            object_store_access_key={'user': {'name': accountuser}})
        accesskey = res.items[0].name
        secretkey = res.items[0].secret_access_key
    except rest.ApiException as e:
        print("Exception when creating object store access key: %s\n" % e)
        exit(1)

    # Find a Data VIP for this FlashBlade.
    datavip=""
    try:
        # list all network interfaces
        res = fb.network_interfaces.list_network_interfaces(filter="services='data'")
        datavip = res.items[0].address
    except rest.ApiException as e:
        print("Exception when listing network interfaces: %s\n" % e)
        exit(1)

    # Create an S3 bucket with the access/secret keys
    bucketname = args.user + "-working"
    endpointurl = "http://" + datavip
    print("Creating bucket %s at endpoint %s\n" % (bucketname,
                                                   endpointurl))
    try:
        s3 = boto3.resource(service_name='s3',use_ssl=False,aws_access_key_id=accesskey,aws_secret_access_key=secretkey,endpoint_url=endpointurl)
        bucket = s3.create_bucket(Bucket=bucketname)
    except:
        print("Failed creating bucket %s\n" % bucketname)

    with open(args.outfile, "w") as outf:
        outf.write("spark.hadoop.fs.s3a.endpoint {}\n".format(datavip))
        outf.write("spark.hadoop.fs.s3a.access.key {}\n".format(accesskey))
        outf.write("spark.hadoop.fs.s3a.secret.key {}\n".format(secretkey))
        outf.write("spark.hadoop.fs.defaultfs s3a://{}/\n".format(bucketname))

        # Add s3a and fileinputformat settings for performance.
        outf.write("spark.hadoop.fs.s3a.fast.upload true\n")
        outf.write("spark.hadoop.fs.s3a.connection.ssl.enabled false\n")
        outf.write("spark.hadoop.mapreduce.fileoutputcommitter.algorithm.version 2\n")
        outf.write("spark.hadoop.mapreduce.input.fileinputformat.split.minsize 541073408\n")
    fb.logout()


if __name__ == '__main__':
    main()
