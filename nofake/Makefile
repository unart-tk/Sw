#
#
#

NOTANGLE    = notangle
NOWEAVE	    = noweave
PDFLATEX    = pdflatex

# -- high-level targets

all:		nofake

clean:
	rm -f nofake.x nofake.y nofake.1

nofake:	nofake.nw
	$(NOTANGLE) -R$@ $< > $@
	chmod +x $@

nofake.1: nofake
	pod2man nofake > nofake.1
	
test:	nofake
	./nofake -Rnofake nofake.nw > nofake.x
	chmod +x nofake.x
	./nofake.x -Rnofake nofake.nw > nofake.y
	diff nofake.x nofake.y && echo "test passed"

# -- documentation

RERUN =     Rerun (LaTeX|to get cross-references right)

pdf:	    $(PDF)

%.pdf:	%.tex 
	    $(PDFLATEX) $<
	    if egrep -s '$(RERUN)' $*.log ;then $(PDFLATEX) $<; fi
	    if egrep -s '$(RERUN)' $*.log ;then $(PDFLATEX) $<; fi

%.inc:      %.nw
	    $(NOWEAVE) -delay $< > $@

%.tex:	%.inc
	    echo "    \documentclass[11pt]{article}	"  > $@
	    echo "    \usepackage{a4wide}		" >> $@
	    echo "    \usepackage{hyperref}		" >> $@
	    echo "    \usepackage{noweb}		" >> $@
	    echo "    \noweboptions{breakcode}		" >> $@
	    echo "    \begin{document}			" >> $@
	    echo "    \input{$<}			" >> $@
	    echo "    \end{document}			" >> $@


