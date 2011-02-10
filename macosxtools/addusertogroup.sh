#!/bin/sh

sudo dscl . append Groups/$2 GroupMembership $1
