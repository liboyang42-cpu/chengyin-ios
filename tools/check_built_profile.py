#!/usr/bin/env python3
"""Verify custom metadata survives Xcode processing; do not print endpoint values."""
import argparse
import plistlib

def validate(value, market):
    if value.get('QuestifyMarket') != market:
        raise ValueError('Built app lacks the expected operational market')
    if 'QuestifyAPIBaseURL' not in value or not isinstance(value['QuestifyAPIBaseURL'], str):
        raise ValueError('Built app lacks an explicit API configuration field')
    if value['QuestifyAPIBaseURL']:
        raise ValueError('Public CI builds must keep the API endpoint empty')

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--plist',required=True);p.add_argument('--market',choices=['CN','US'],required=True)
    args=p.parse_args()
    with open(args.plist,'rb') as f:validate(plistlib.load(f),args.market)
    print('Verified built market metadata and intentionally empty API configuration:',args.market)
