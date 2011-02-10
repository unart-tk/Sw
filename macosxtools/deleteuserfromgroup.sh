#!/bin/sh

sudo dscl . delete Groups/$2 GroupMembership $1
