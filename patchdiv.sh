

c=0
for i in 1 $(grep -n ^diff "$1" | cut -d: -f1) $(wc -l "$1" | cut -d' ' -f1); do
	if [ -z "$a" ]; then a=$i; continue; fi
	b=$i; head -n$[b-1] "$1" | tail -n$[b-a] >$c.patch; a=""; let c++
done

