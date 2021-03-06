=head1 LICENSE

Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

# $Id$

package EnsEMBL::Web::ViewConfig::Variation::Mappings;

use strict;

use base qw(EnsEMBL::Web::ViewConfig);

sub init {
  my $self = shift;
  
  $self->set_defaults({
    motif_scores       => 'no'
  });

  $self->title = 'Genes and regulation';
}

sub form {
  my $self = shift;
  
  if ($self->hub->species =~ /homo_sapiens|mus_musculus/i) {
    $self->add_form_element({
      type  => 'CheckBox',
      label => 'Show regulatory motif binding scores',
      name  => 'motif_scores',
      value => 'yes',
      raw   => 1,
    });
  }
}

1;
