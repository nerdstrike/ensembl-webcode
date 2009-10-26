package EnsEMBL::Web::Component::Gene::ComparaTree;

use strict;
use warnings;
no warnings "uninitialized";
use base qw(EnsEMBL::Web::Component::Gene);

use EnsEMBL::Web::Constants;
use Bio::AlignIO;
use IO::Scalar;

sub _init {
  my $self = shift;
  $self->cacheable( 0 );
  $self->ajaxable(  1 );
}

sub caption {
  return undef;
}

sub _get_details {
  my $self = shift;
  my $object = $self->object;
  my $member = $object->get_compara_Member;
  return (undef, "<B>Gene is not in the compara database</B>", '') unless $member;

  my $tree   = $object->get_ProteinTree;
  return (undef, "<B> Gene is not in a compara protein tree </B>",     "<p>Could not get protein tree in compara for this gene</p>") unless $tree;

  my $node   = $tree->get_leaf_by_Member($member);
  return(undef,"<B> Gene is not in the compara tree </B>", sprintf( q(<p>Member %s not in compara tree %s</p>), $member->stable_id, $tree->node_id )) unless $node;

  return ($member,$tree,$node);
}

sub content {
  my $self           = shift;
  my $object         = $self->object;

  #----------
  # Get the Member and ProteinTree objects 
  #----------
  # Draw the tree

  my ( $member,$tree,$node ) = $self->_get_details;
  return $tree if !defined $member;

  my $leaves = $tree->get_all_leaves;

  my $highlight_gene     = $object->param('g1');
  my $highlight_ancestor = $object->param('anc');
  my $highlight_species;
  my $highlight_genome_db_id;
  if ($highlight_gene) {
    my $highlight_gene_display_label;
    foreach my $this_leaf (@$leaves) {
      if ($highlight_gene and $this_leaf->gene_member->stable_id eq $highlight_gene) {
        $highlight_gene_display_label = $this_leaf->gene_member->display_label || $highlight_gene;
        $highlight_species = $this_leaf->gene_member->genome_db->name;
        $highlight_genome_db_id = $this_leaf->gene_member->genome_db_id;
        last;
      }
    }

    if ($highlight_species) {
      print $self->_info( 'Highlighted genes', "In addition to all <I>".$member->genome_db->name. "</I> genes,".
          " the $highlight_gene_display_label gene (<I>$highlight_species</I>) and its paralogues have been highlighted. ".
          "<a href=".$object->_url().">Click here to switch off highlighting</a>." );
    } else {
      print $self->_warning( 'WARNING', "$highlight_gene gene is not in this Gene Tree" );
      $highlight_gene = undef;
    }
  }

  my $wuc          = $object->image_config_hash( 'genetreeview' );
  my $image_width  = $self->image_width || 800;
  my $collapsability = $object->param('collapsability') || 'gene';
  my $colouring    = $object->param('colouring') || 'background';
  my @hidden_clades  = grep {$_ =~ /^group_/ and $object->param($_) eq "hide"} $object->param();
  my @collapsed_clades  = grep {$_ =~ /^group_/ and $object->param($_) eq "collapse"} $object->param();

  my $hidden_genome_db_ids;
  my $hidden_genes_counter = 0;
  if (@hidden_clades) {
    $hidden_genome_db_ids = "_";
    foreach my $clade (@hidden_clades) {
      my ($clade_name) = $clade =~ /group_([\w\-]+)_display/;
      $hidden_genome_db_ids .= $object->param("group_${clade_name}_genome_db_ids") . "_";
    }
    foreach my $this_leaf (@$leaves) {
      my $genome_db_id = $this_leaf->genome_db_id;
      next if ($highlight_genome_db_id and $genome_db_id eq $highlight_genome_db_id);
      next if ($highlight_gene and $this_leaf->gene_member->stable_id eq $highlight_gene);
      next if ($genome_db_id == $member->genome_db_id);
      if ($hidden_genome_db_ids =~ /_${genome_db_id}_/) {
        $hidden_genes_counter++;
        $this_leaf->disavow_parent;
        $tree = $tree->minimize_tree;
      }
    }
    if ($hidden_genes_counter) {
      print $self->_info("Hidden genes", "There are $hidden_genes_counter hidden genes in the tree. Use the 'configure page' link in the left panel to change the options.");
    }
  }

  $wuc->set_parameters({
    'container_width'   => $image_width,
    'image_width',      => $image_width,
    'slice_number',     => '1|1',
  });

  #$wuc->tree->dump("GENE TREE CONF", '([[caption]])');
  my @highlights = ($object->stable_id, $member->genome_db->dbID);
  # Keep track of collapsed nodes

  my $collapsed_nodes = $object->param('collapse');
  
  my $collapsed_to_gene = $self->_collapsed_nodes($tree,$node, 'gene', $highlight_genome_db_id, $highlight_gene);
  my $collapsed_to_para = $self->_collapsed_nodes($tree,$node, 'paralogs', $highlight_genome_db_id, $highlight_gene);
  my $collapsed_to_dups = $self->_collapsed_nodes($tree,$node, 'duplications', $highlight_genome_db_id, $highlight_gene);

  unless( defined( $collapsed_nodes ) ){ #Examine collapsabilty
    $collapsed_nodes = $collapsed_to_gene if( $collapsability eq 'gene');
    $collapsed_nodes = $collapsed_to_para if( $collapsability eq 'paralogs');
    $collapsed_nodes = $collapsed_to_dups if( $collapsability eq 'duplications');
    $collapsed_nodes ||= '';
  }

  # print $self->_info("Collapsed nodes",  join(" -- ", split(",", $collapsed_nodes)));
  if (@collapsed_clades) {
    foreach my $clade (@collapsed_clades) {
      my ($clade_name) = $clade =~ /group_([\w\-]+)_display/;
      my $extra_collapsed_nodes = _find_nodes_by_genome_db_ids($tree,
          [split("_", $object->param("group_${clade_name}_genome_db_ids"))], "internal");
      if (%$extra_collapsed_nodes) {
        $collapsed_nodes .= "," if ($collapsed_nodes);
        $collapsed_nodes .= join(",", keys %$extra_collapsed_nodes);
      }
    }
    # print $self->_info("Collapsed nodes",  join(" -- ", split(",", $collapsed_nodes)));
  }

  my $coloured_nodes;
  if (($colouring eq "background") or ($colouring eq "foreground")) {
    my $mode = "bg";
    $mode = "fg" if ($colouring eq "foreground");

    my @clades = grep {$_ =~ /^group_.+_${mode}colour/ } $object->param();

    # Get all the genome_db_ids in each clade
    my $genome_db_ids_by_clade;
    foreach my $clade (@clades) {
      my ($clade_name) = $clade =~ /group_(.+)_${mode}colour/;
      $genome_db_ids_by_clade->{$clade_name} = [split("_", $object->param("group_${clade_name}_genome_db_ids"))]
    }

    # Sort the clades by the number of genome_db_ids. First the largest clades,
    # so they can be overwritten later (see ensembl-draw/modules/Bio/EnsEMBL/GlyphSet/genetree.pm)
    foreach my $clade_name (sort {
          scalar(@{$genome_db_ids_by_clade->{$b}}) <=> scalar(@{$genome_db_ids_by_clade->{$a}})
	} keys %$genome_db_ids_by_clade) {
      my $genome_db_ids = $genome_db_ids_by_clade->{$clade_name};
      my $colour = $object->param("group_${clade_name}_${mode}colour") || "magenta";
      my $these_coloured_nodes;
      if ($mode eq "fg") {
        $these_coloured_nodes = _find_nodes_by_genome_db_ids($tree, $genome_db_ids, "all");
      } else {
        $these_coloured_nodes = _find_nodes_by_genome_db_ids($tree, $genome_db_ids);
      }
      if (%$these_coloured_nodes) {
        push(@$coloured_nodes, {
	    'clade' => $clade_name,
	    'colour' => $colour,
	    'mode' => $mode,
	    'node_ids' => [keys %$these_coloured_nodes],
	    });
        # print $self->_info("Coloured nodes ($clade_name - $colour)",  join(" -- ", keys %$these_coloured_nodes));
      }
    }
  }

  push @highlights, $collapsed_nodes || undef;

  push @highlights, $coloured_nodes || undef;

  push @highlights, $highlight_genome_db_id || undef;

  push @highlights, $highlight_gene || undef;

  push @highlights, $highlight_ancestor || undef;

  my $image  = $self->new_image
      ( $tree, $wuc, [@highlights] );
  return if $self->_export_image($image, 'no_text');

#  $image->cacheable   = 'yes';

  $image->image_type  = 'genetree';
  $image->image_name  = ($object->param('image_width')).'-'.$object->stable_id;
  $image->imagemap    = 'yes';

  $image->{'panel_number'} = 'tree';
  $image->set_button( 'drag', 'title' => 'Drag to select region' );

  my $info;
  my $li_tmpl = qq(<li><a href="%s">%s</a></li>);
  my @view_links;

  push @view_links, sprintf( $li_tmpl,
                             $object->_url({'collapse'=>$collapsed_to_gene,'g1'=>$highlight_gene}),
                             $highlight_gene?'View current genes only':'View current gene only');

  push @view_links, sprintf( $li_tmpl,
                             $object->_url({'collapse'=>$collapsed_to_para,'g1'=>$highlight_gene}),
                             $highlight_gene?'View paralogs of current genes':'View paralogs of current gene');

  push @view_links, sprintf( $li_tmpl,
                             $object->_url({'collapse'=>$collapsed_to_dups,'g1'=>$highlight_gene}),
                             'View all duplication nodes');

  push @view_links, sprintf( $li_tmpl,
                             $object->_url({'collapse'=>'','g1'=>$highlight_gene}),
                             'View fully expanded tree');

  if ($highlight_gene) {
    push @view_links, sprintf( $li_tmpl,
                             $object->_url(),
                             'Switch off highlighting');
  }

  my $view_options_html = sprintf( qq(
<div style="margin-top:1em"><b>View options:</b><br/>
<small><ul>%s</ul></small>
Use the 'configure page' link in the left panel to set the default. Further options are available from menus on individual tree nodes.</div>), join( '', @view_links) );

  return $image->render . $info . $view_options_html ;
}

sub _collapsed_nodes{
  # Takes the ProteinTree and node related to this gene and a view action
  # ('gene', 'paralogs', 'duplications' ) and returns the list of
  # tree nodes that should be collapsed according to the view action.
  # TODO: Move to Object::Gene, as the code is shared by the ajax menus
  my $self = shift;
  my $tree = shift;
  my $node = shift;
  my $action = shift;
  my $highlight_genome_db_id = shift;
  my $highlight_gene = shift;
  $tree->isa('Bio::EnsEMBL::Compara::ProteinTree') 
      || die( "Need a ProteinTree, not a $tree" );
  $node->isa('Bio::EnsEMBL::Compara::AlignedMember')
      || die( "Need an AlignedMember, not a $node" );

  my %collapsed_nodes;
  my %expanded_nodes;
  
  if( $action eq 'gene' ){ # View current gene
    foreach my $adj( @{$node->get_all_adjacent_subtrees} ){
      $collapsed_nodes{$adj->node_id} = $_;
    }
    if ($highlight_gene) {
      foreach my $ancestor( @{$node->get_all_ancestors} ){
        $expanded_nodes{$ancestor->node_id} = $ancestor;
      }
      foreach my $leaf( @{$tree->get_all_leaves} ){
        foreach my $adj( @{$leaf->get_all_adjacent_subtrees} ){
          $collapsed_nodes{$adj->node_id} = $_;
        }
        if( $leaf->gene_member->stable_id eq $highlight_gene ){
          foreach my $ancestor( @{$leaf->get_all_ancestors} ){
            $expanded_nodes{$ancestor->node_id} = $ancestor;
          }
          last;
        }
      }
    }
  }
  elsif( $action eq 'paralogs' ){ # View all paralogs
    my $gdb_id = $node->genome_db_id;
    foreach my $leaf( @{$tree->get_all_leaves} ){
      if( $leaf->genome_db_id == $gdb_id or ($highlight_genome_db_id and $leaf->genome_db_id == $highlight_genome_db_id) ){
        foreach my $ancestor( @{$leaf->get_all_ancestors} ){
          $expanded_nodes{$ancestor->node_id} = $ancestor;
        }
        foreach my $adjacent( @{$leaf->get_all_adjacent_subtrees} ){
          $collapsed_nodes{$adjacent->node_id} = $adjacent;
        }
      }
    }
  }
  elsif( $action eq 'duplications' ){ # View all duplications
    foreach my $tnode( @{$tree->get_all_nodes} ){
      next if $tnode->is_leaf;
      if($tnode->get_tagvalue('dubious_duplication') or
         ! $tnode->get_tagvalue('Duplication') ){
        $collapsed_nodes{$tnode->node_id} = $tnode;
        next;
      }
      $expanded_nodes{$tnode->node_id} = $tnode;
      foreach my $ancestor( @{$tnode->get_all_ancestors} ){
        $expanded_nodes{$ancestor->node_id} = $ancestor;
      }
    }
  }
  my $collapsed_node_ids
      = join( ',', grep{! $expanded_nodes{$_}} keys %collapsed_nodes );
  return $collapsed_node_ids;
}

sub _find_nodes_by_genome_db_ids {
  my ($tree, $genome_db_ids, $mode) = @_;
  my $node_ids = {};

  if ($tree->is_leaf()) {
    my $genome_db_id = $tree->genome_db_id;
    if (grep {$_ eq $genome_db_id} @$genome_db_ids) {
      $node_ids->{$tree->node_id} = 1;
    }
  } else {
    my $tag = 1;
    foreach my $this_child (@{$tree->children}) {
      my $these_node_ids = _find_nodes_by_genome_db_ids($this_child, $genome_db_ids, $mode);
      foreach my $node_id (keys %$these_node_ids) {
        $node_ids->{$node_id} = 1;
      }
      $tag = 0 if (!$node_ids->{$this_child->node_id});
    }
    if ($mode eq "internal") {
      foreach my $this_child (@{$tree->children}) {
        delete($node_ids->{$this_child->node_id}) if $this_child->is_leaf();
      }
    }
    if ($tag) {
      unless ($mode eq "all") {
        foreach my $this_child (@{$tree->children}) {
          delete($node_ids->{$this_child->node_id});
        }
      }
      $node_ids->{$tree->node_id} = 1;
    }
  }

delete($node_ids->{403985}) if ($mode eq "internal");
  return $node_ids;
}

sub content_align {
  my $self           = shift;
  my $object         = $self->object;

  #----------
  # Get the ProteinTree object
  my ( $member,$tree,$node ) = $self->_get_details;
  return $tree if !defined $member;

  #----------
  # Return the text representation of the tree
  my $htmlt = q(
<p>Multiple sequence alignment in "<i>%s</i>" format:</p>
<p>The sequence alignment format can be configured using the
'configure page' link in the left panel.<p>
<pre>%s</pre>);

  #----------
  # Determine the format
  my %formats = EnsEMBL::Web::Constants::ALIGNMENT_FORMATS();
  my $mode = $object->param('text_format');
     $mode = 'fasta' unless $formats{$mode};
  my $fmt_caption = $formats{$mode} || $mode;

  my $align_format = $mode;

  my $formatted; # Variable to hold the formatted alignment string
  my $SH = IO::Scalar->new(\$formatted);
  #print $SH "FOO\n";
  my $aio = Bio::AlignIO->new( -format => $align_format, -fh => $SH );
  $aio->write_aln( $tree->get_SimpleAlign );

  return $object->param('_format') eq 'Text'
       ? $formatted 
       : sprintf( $htmlt, $fmt_caption, $formatted )
       ;
}

sub content_text {
  my $self           = shift;
  my $object         = $self->object;

  #----------
  # Get the ProteinTree object
  my ( $member,$tree,$node ) = $self->_get_details;
  return $tree if !defined $member;

  #----------
  # Template for the section HTML
  my $htmlt = q(
<p>The following is a representation of the tree in "<i>%s</i>" format</p>
<p>The tree representation can be configured using the
'configure page' link in the left panel.<p>
<pre>%s</pre>);


  #----------
  # Return the text representation of the tree
  my %formats = EnsEMBL::Web::Constants::TREE_FORMATS();
  my $mode = $object->param('tree_format');
     $mode = 'newick' unless $formats{$mode};
  my $fn   = $formats{$mode}{'method'};
  my $fmt_caption = $formats{$mode}{caption} || $mode;

  my @params = ( map { $object->param( $_ ) } 
                 @{ $formats{$mode}{'parameters'} || [] } );
  my $string = $tree->$fn(@params);
  if( $formats{$mode}{'split'} && $object->param('_format') ne 'Text') {
    my $reg = '(['.quotemeta($formats{$mode}{'split'}).'])';
    $string =~ s/$reg/$1\n/g;
  }

  return $object->param('_format') eq 'Text'
       ? $string 
       : sprintf( $htmlt, $fmt_caption, $string )
       ;
}

1;
