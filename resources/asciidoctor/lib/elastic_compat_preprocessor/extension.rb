require 'asciidoctor/extensions'

include Asciidoctor

# Preprocessor to turn Elastic's "wild west" formatted block extensions into
# standard asciidoctor formatted extensions
#
# Turns
#   added[6.0.0-beta1]
# Into
#   added::[6.0.0-beta1]
# Because `::` is required by asciidoctor but isn't by asciidoc.
#
# Turns
#   include-tagged::foo[tag]
# Into
#   include::elastic-include-tagged:foo[tag]
# To chain into the ElasticIncludeTagged processor which is *slightly* different
# than asciidoctor's built in tagging support.
#
# Turns
#   --
#   :api: bulk
#   :request: BulkRequest
#   :response: BulkResponse
#   --
# Into
#   :api: bulk
#   :request: BulkRequest
#   :response: BulkResponse
# Because asciidoctor clears attributes set in a block. See
# https://github.com/asciidoctor/asciidoctor/issues/2993
#
# Turns
#   ["source","sh",subs="attributes"]
#   --------------------------------------------
#   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-{version}.zip
#   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-{version}.zip.sha512
#   shasum -a 512 -c elasticsearch-{version}.zip.sha512 <1>
#   unzip elasticsearch-{version}.zip
#   cd elasticsearch-{version}/ <2>
#   --------------------------------------------
#   <1> Compares the SHA of the downloaded `.zip` archive and the published checksum, which should output
#       `elasticsearch-{version}.zip: OK`.
#   <2> This directory is known as `$ES_HOME`.
#
# Into
#   ["source","sh",subs="attributes,callouts"]
#   --------------------------------------------
#   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-{version}.zip
#   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-{version}.zip.sha512
#   shasum -a 512 -c elasticsearch-{version}.zip.sha512 <1>
#   unzip elasticsearch-{version}.zip
#   cd elasticsearch-{version}/ <2>
#   --------------------------------------------
#   <1> Compares the SHA of the downloaded `.zip` archive and the published checksum, which should output
#       `elasticsearch-{version}.zip: OK`.
#   <2> This directory is known as `$ES_HOME`.
# Because asciidoc adds callouts to all "source" blocks. We'd *prefer* to do
# this in the tree processor because it is less messy but we can't because
# asciidoctor checks the `:callout` sub before giving us a chance to add it.
#
class ElasticCompatPreprocessor < Extensions::Preprocessor
  IncludeTaggedDirectiveRx = /^include-tagged::([^\[][^\[]*)\[(#{CC_ANY}+)?\]$/
  SourceWithSubsRx = /^\["source", ?"[^"]+", ?subs="(#{CC_ANY}+)"\]$/

  def process document, reader
    reader.instance_variable_set :@in_attribute_only_block, false
    def reader.process_line line
      return line unless @process_lines

      if @in_attribute_only_block
        if line == '--'
          @in_attribute_only_block = false
          line.clear
        else
          line
        end
      elsif IncludeTaggedDirectiveRx =~ line
        if preprocess_include_directive "elastic-include-tagged:#{$1}", $2
          nil
        else
          # the line was not a valid include line and we've logged a warning
          # about it so we should do the asciidoctor standard thing and keep
          # it intact. This is how we do that.
          @look_ahead += 1
          line
        end
      elsif line == '--'
        lines = self.lines
        lines.shift
        while Asciidoctor::AttributeEntryRx =~ (check_line = lines.shift)
        end
        if check_line == '--'
          @in_attribute_only_block = true
          line.clear
        else
          line
        end
      elsif SourceWithSubsRx =~ line
        line = super
        unless $1.include?('callouts')
          line.sub! "subs=\"#{$1}\"", "subs=\"#{$1},callouts\""
        end
        line
      else
        line = super
        line&.gsub!(/(added)\[([^\]]*)\]/, '\1::[\2]')
      end
    end
    reader
  end
end
