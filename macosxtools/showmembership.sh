#!/bin/sh

dscl . read /Groups/$1 GroupMembership
