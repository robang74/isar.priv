#!/bin/env bash

function pcmp() {(
	set -m
	local n=$(nproc)
	find /usr/share -not -type d > list.txt
	split -n l/$n list.txt
	for i in x??; do
		tar -I "zstd -2 -T$n" -cpSf $i.tar.zstd --files-from=$i 2>/dev/null &
		printf "$i.tar.zstd "
	done
	while fg >/dev/null 2>&1; do :; done
	tar -cpSf pcmp.tar x??.tar.zstd && rm -f x??.tar.zstd
	printf "\npcmp.tar\n"
)}

function scmp() {
	tar -I "zstd -2 -T8" -cpSf test.tar.zstd /usr/share 2>/dev/null
}

function pdcm() {(
	set -m
	local n=$(nproc)
	tar -xpSf pcmp.tar
	for i in x??.tar.zstd; do
		tar -I "unzstd -T$n" -xpSf $i -C tmp 2>/dev/null &
		printf "$i "
	done
	while fg >/dev/null 2>&1; do printf "\nDONE\n"; done
)}

function sdcm() {
	tar -I "unzstd -T8" -xpSf test.tar.zstd -C tmp 2>/dev/null
}

function pcpy() {(
	set -m
	local n=$(nproc)
	find /usr/share -not -type d > list.txt
	split -n l/$n list.txt
	for i in x??; do
		tar -cpSO --files-from=$i | tar -xpSC dst &
		printf "$i "
	done 2>/dev/null
	while fg >/dev/null 2>&1; do :; done
)}

