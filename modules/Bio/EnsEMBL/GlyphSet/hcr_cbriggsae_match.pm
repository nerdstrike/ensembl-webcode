package Bio::EnsEMBL::GlyphSet::hcr_cbriggsae_match;
use strict;
use vars qw(@ISA);
# use Bio::EnsEMBL::GlyphSet_simple;
# @ISA = qw(Bio::EnsEMBL::GlyphSet_simple);
use Bio::EnsEMBL::GlyphSet_feature2;
@ISA = qw(Bio::EnsEMBL::GlyphSet_feature2);


sub my_label { return "Cb high cons"; }

sub features {
    my ($self) = @_;
    
    my $assembly = 
      EnsWeb::species_defs->other_species('Caenorhabditis_briggsae')->{'ENSEMBL_GOLDEN_PATH'};
    return [] unless $assembly;

    return $self->{'container'}->get_all_compara_DnaAlignFeatures(
							   'Caenorhabditis briggsae',
							    $assembly,'WGA_HCR');

}

sub href {
    my ($self, $chr_pos ) = @_;
    return "/Caenorhabditis_briggsae/$ENV{'ENSEMBL_SCRIPT'}?$chr_pos";
}

sub zmenu {
    my ($self, $id, $chr_pos ) = @_;
    return { 
	'caption'    => $id, 
	'Jump to Caenorhabditis briggsae' => $self->href( $chr_pos )
    };
}


sub unbumped_zmenu {
    my ($self, $ref, $target,$width ) = @_;
    my ($chr,$pos) = @$target;
    my $chr_pos = "l=$chr:".($pos-$width)."-".($pos+$width);
    return { 
    	'caption'    => 'Dot-plot', 
    	'Dotter' => $self->unbumped_href( $ref, $target ),
        'Jump to Caenorhabditis briggsae' => $self->href( $chr_pos )
    };
}

sub unbumped_href {
    my ($self, $ref, $target ) = @_;
    return "/$ENV{'ENSEMBL_SPECIES'}/dotterview?ref=".join(':',$ENV{'ENSEMBL_SPECIES'},@$ref).
                        "&hom=".join(':','Caenorhabditis_briggsae', @$target ) ;
}

1;
