package EnsEMBL::Web::Command::UserData::AttachDAS;

use strict;
use warnings;

use EnsEMBL::Web::RegObj;
use Bio::EnsEMBL::ExternalData::DAS::CoordSystem;
use base qw(EnsEMBL::Web::Command);
use EnsEMBL::Web::Filter::DAS;

sub process {
  my $self = shift;
  my $object = $self->object;
  my $url = $object->species_path($object->data_species).'/UserData/';
  my ($next, $param);

  my $server = $object->param('das_server');

  if ($server) {
    my $filter = EnsEMBL::Web::Filter::DAS->new({'object'=>$object});
    my $sources = $filter->catch($server, $object->param('logic_name'));
    if ($filter->error_code) {
      $url .= 'SelectDAS';
      $param->{'filter_module'} = 'DAS';
      $param->{'filter_code'} = $filter->error_code;
    }
    else {
    
      my @success = ();
      my @skipped = ();

      foreach my $source (@{ $sources }) {
        # Fill in missing coordinate systems
        if (!scalar @{ $source->coord_systems }) {
          my @expand_coords = grep { $_ } $object->param($source->logic_name.'_coords');
          #warn "EXPANDED COORDS @expand_coords";
          if (scalar @expand_coords) {
            @expand_coords = map {
              Bio::EnsEMBL::ExternalData::DAS::CoordSystem->new_from_string($_)
            } @expand_coords;
            $source->coord_systems(\@expand_coords);
          }
          else {
            $param->{'filter_module'} = 'DAS';
            $param->{'filter_code'} = 'no_coords';
            #warn 'DAS ERROR: Source '.$source->logic_name.' has no coordinate systems and none were selected.';
          }
        }

        # NOTE: at present the interface only allows adding a source that has not
        # already been added (by disabling their checkboxes). Thus this call
        # should always evaluate true at present.
        if( $object->get_session->add_das( $source ) ) {
          push @success, $source->logic_name;
        } 
        else {
          push @skipped, $source->logic_name;
        }
        #  Either way, turn the source on...
        $object->get_session->configure_das_views(
          $source,
          $object->_parse_referer( $object->param('_referer') )
        );
      }
      $object->get_session->save_das;
      $object->get_session->store;
      $url .= 'DasFeedback';
      $param->{'added'} = \@success;
      $param->{'skipped'} = \@skipped;
    }
  }
  else {
    $next = 'SelectDAS';
    $param->{'filter_module'} = 'DAS';
    $param->{'filter_code'} = 'no_server';
  }

  $self->ajax_redirect($url.$next, $param);
}

1;
