#!/usr/bin/python3

import argparse
import os

# Import Purity//FB SDK
from purity_fb import PurityFb, Bucket, ObjectStoreAccessKey, Reference, rest

# Disable warnings related to unsigned SSL certificates.
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--account", default='datateam', help="Service account name.")
    parser.add_argument("--user", default='spark', help="Account user name.")
    parser.add_argument("--outfile", default='credentials',
                        help="Output file for key credentials.")
    args = parser.parse_args()

    # Create PurityFb object for a certain array using environment variables.
    FB_MGMT = os.environ.get('FB_MGMT_VIP')
    TOKEN = os.environ.get('FB_MGMT_TOKEN')

    # Fail fast if necessary env variables not available.
    if not FB_MGMT or not TOKEN:
        print("Requires environment variables for logging into FlashBlade REST: please set FB_MGMT_VIP and FB_MGMT_TOKEN")
        exit(1)

    # Step 1: login to the FlashBlade management API
    fb = PurityFb(FB_MGMT)
    fb.disable_verify_ssl()
    try:
        fb.login(TOKEN)
    except rest.ApiException as e:
        print("Exception: %s\n" % e)
        exit()

    # Step 2: Create service account
    try:
        res = fb.object_store_accounts.create_object_store_accounts(names=[args.account])
        print("Creating service account {}".format(args.account))
    except:
        print("Service account {} already exists".format(args.account))

    # Step 3: Create user account
    accountuser = args.account + '/' + args.user

    try:
        # post the object store user object myobjuser on the array
        print("Creating user account {}".format(accountuser))
        res = fb.object_store_users.create_object_store_users(names=[accountuser])
    except:
        print("User %s creation failed.".format(accountuser))

    # Step 4: Create access keys

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

    # Step 5: Create bucket
    bucketname = args.user + "-working"
    print("Creating bucket %s\n" % bucketname)

    try:
        attr = Bucket()
        # Each bucket must be associated with a service account.
        attr.account = Reference(name=args.account)
        res = fb.buckets.create_buckets(names=[bucketname], account=attr)
    except rest.ApiException as e:
        print("Exception when creating bucket: %s\n" % e)

    # Output
    with open(args.outfile, "w") as outf:
        outf.write("AWS_ACCESS_KEY_ID={}\n".format(accesskey))
        outf.write("AWS_SECRET_ACCESS_KEY_ID={}\n".format(secretkey))

    print("Access newly created bucket in Spark at s3a://{}/".format(bucketname))

    fb.logout()


if __name__ == '__main__':
    main()
