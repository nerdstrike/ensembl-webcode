package Bio::EnsEMBL::GlyphSet::pfam;
use strict;
use vars qw(@ISA);
use lib "..";
use Bio::EnsEMBL::GlyphSet;
@ISA = qw(Bio::EnsEMBL::GlyphSet);
use Bio::EnsEMBL::Glyph::Rect;
use Bio::EnsEMBL::Glyph::Text;
use Bio::EnsEMBL::Glyph::Composite;

sub _init {
    my ($this, $protein, $Config) = @_;

    my $y          = 0;
    my $h          = 8;
    my $highlights = $this->highlights();

    my @pfam;

    foreach my $feat ($protein->each_Protein_feature()) {
	if ($feat->hdbname =~ /^PF\w+/) {
	    push (@pfam,$feat);
	}
    }
	
    if (@pfam) {
	my $Composite = new Bio::EnsEMBL::Glyph::Composite({
	    'id'    => $feat->hdbname(),
	    'zmenu' => {
		'caption'  => $feat->hdbname(),
		'01:kung'     => 'opt1',
		'02:foo'      => 'opt2',
		'03:fighting' => 'opt3'
			},
			});

	my $colour = $Config->get('transview','transcript','col');
	$colour    = $Config->get('transview','transcript','hi') if(defined $highlights && $highlights =~ /\|$vgid\|/);
	
	    foreach my $pf (@pfam) {
		my $x = $pf->feature1->start();
		my $w = $pf->feature1->end - $x;
		
		my $rect = new Bio::EnsEMBL::Glyph::Rect({
		    'x'        => $x,
		    'y'        => $y,
		    'width'    => $w,
		    'height'   => $h,
		    'id'       => $exon->id(),
		    'colour'   => $colour,
		    'zmenu' => {
			'caption' => $pf->seqname->id(),
			},
		});
		    
		
		$Composite->push($rect) if(defined $rect);
		
	    }
	    #########
	    # replace this with bumping!
	    #
	    push @{$this->{'glyphs'}}, $Composite;
	    $y+=$h;
	}
	
    }
}
1;


