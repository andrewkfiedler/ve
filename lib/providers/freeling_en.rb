# Encoding: UTF-8

# TODO: Retain capitalization in lemmas?
# TODO: Memoize

require 'open3'

class Sprakd
  class Provider
    class FreelingEn < Sprakd::Provider

      BIT_STOP = 'SprakdEnd'
  
      def initialize(config = {})
        @config = {:app => 'analyzer',
                   :path => '',
                   :flags => ''}.merge(config)
    
        @config[:app] = `which #{@config[:app]}`.strip!
        local = @config[:app] =~ /local/ ? '/local' : ''
        @config[:flags] = "-f /usr#{local}/share/FreeLing/config/en.cfg --flush --nonumb"
        
        @is_working = false        
        start!
      end
  
      # Interface methods
  
      def works?
        (["Wrote write VBD 1", ""] == parse('Wrote').tokens.collect { |t| t[:raw] })
      end
  
      # Talks to the app and returns a parse object
      def parse(text)
        @stdin.puts "#{text}\n#{BIT_STOP}\n"
        output = []
        
        while line = @stdout.readline
          if line =~ /#{BIT_STOP}/x
            @stdout.readline
            break
          end
          output << line
        end
        
        Sprakd::Parse::FreelingEn.new(text, output)
      end

      private
  
      def start!
        @stdin, @stdout, @stderr = Open3.popen3("#{@config[:app]} #{@config[:flags]}")
        @is_working = works?
      rescue
        @is_working = false
      end
  
    end
  end
end

class Sprakd
  class Parse
    class FreelingEn < Sprakd::Parse
      
      attr_reader :tokens, :text
      
      def initialize(text, output)
        @tokens = []
        @text = text
        position = 0
        
        output.each_with_index do |line, index|
          line.rstrip!
          token = {:raw => line}

          # Anything unparsed at the end of the text
          # This must happen before sentence splits are detected to avoid funny ordering
          if output.size > 1 && output.size == index + 1
            unparsed_md = %r{(.*? \Z\n?)}mx.match(text, position)
            if unparsed_md[1].length > 0
              unparsed_token = {:type => :unparsed, :literal => unparsed_md[1], :raw => ''}
              @tokens << unparsed_token
            end
          end
            
          # Sentence splits are just empty lines in Freeling
          if line.size == 0
            token[:type] = :sentence_split
            token[:literal] = ''
            @tokens << token
            next
          end
          
          # The parsed token
          info = line.split(/\s/)
          token[:type] = :parsed
          [:literal, :lemma, :pos, :accuracy].each_with_index do |attr, i|
            token[attr] = info[i]
          end
          
          # Anything unparsed preceding this token
          unparsed_md = %r{(.*?) #{Regexp.quote(token[:literal])}}mx.match(text, position)
          if unparsed_md && unparsed_md[1].length > 0
            unparsed_token = {:type => :unparsed, :literal => unparsed_md[1]}
            @tokens << unparsed_token
            position += unparsed_token[:literal].length
          end

          position += token[:literal].length
          @tokens << token
        end
      end
      
      INTERNAL_INFO_FOR_PARSED_POS = {
        'CC' => [Sprakd::PartOfSpeech::Conjunction, nil],
        'CD' => [Sprakd::PartOfSpeech::Number, nil],
        'DT' => [Sprakd::PartOfSpeech::Determiner, nil],
        'EX' => [Sprakd::PartOfSpeech::Pronoun, nil],
        'FW' => [Sprakd::PartOfSpeech::Unknown, nil],
        'Fp' => [Sprakd::PartOfSpeech::Symbol, nil], # .
        'Fc' => [Sprakd::PartOfSpeech::Symbol, nil], # ,
        'Fd' => [Sprakd::PartOfSpeech::Symbol, nil], # :
        'Fx' => [Sprakd::PartOfSpeech::Symbol, nil], # ;
        'Fat' => [Sprakd::PartOfSpeech::Symbol, nil], # !
        'Fit' => [Sprakd::PartOfSpeech::Symbol, nil], # ?
        'IN' => [Sprakd::PartOfSpeech::Preposition, nil],
        'JJ' => [Sprakd::PartOfSpeech::Adjective, nil],
        'JJR' => [Sprakd::PartOfSpeech::Conjunction, :comparative],
        'JJS' => [Sprakd::PartOfSpeech::Conjunction, :superlative],
        'LS' => [Sprakd::PartOfSpeech::Unknown, nil],
        'MD' => [Sprakd::PartOfSpeech::Verb, :modal],
        'NN' => [Sprakd::PartOfSpeech::Noun, nil],
        'NNS' => [Sprakd::PartOfSpeech::Noun, :plural],
        'NNP' => [Sprakd::PartOfSpeech::ProperNoun, nil],
        'NNPS' => [Sprakd::PartOfSpeech::ProperNoun, :plural],
        'PDT' => [Sprakd::PartOfSpeech::Determiner, nil],
        'PRP' => [Sprakd::PartOfSpeech::Pronoun, :personal],
        'PRP$' => [Sprakd::PartOfSpeech::Pronoun, :possessive],
        'RB' => [Sprakd::PartOfSpeech::Adverb, nil],
        'RBR' => [Sprakd::PartOfSpeech::Adverb, :comparative],
        'RBS' => [Sprakd::PartOfSpeech::Adverb, :superlative],
        'RP' => [Sprakd::PartOfSpeech::Postposition, nil],
        'SYM' => [Sprakd::PartOfSpeech::Symbol, nil],
        'TO' => [Sprakd::PartOfSpeech::Preposition, nil],
        'UH' => [Sprakd::PartOfSpeech::Interjection, nil],
        'VB' => [Sprakd::PartOfSpeech::Verb, nil],
        'VBD' => [Sprakd::PartOfSpeech::Verb, :past],
        'VBG' => [Sprakd::PartOfSpeech::Verb, :present_participle],
        'VBN' => [Sprakd::PartOfSpeech::Verb, :past_participle],
        'VBP' => [Sprakd::PartOfSpeech::Verb, nil],
        'VBZ' => [Sprakd::PartOfSpeech::Verb, nil],
        'WDT' => [Sprakd::PartOfSpeech::Determiner, nil],
        'WP' => [Sprakd::PartOfSpeech::Pronoun, nil],
        'WP$' => [Sprakd::PartOfSpeech::Pronoun, :possessive],
        'WRB' => [Sprakd::PartOfSpeech::Adverb, nil],
        'Z' => [Sprakd::PartOfSpeech::Determiner, nil]
      }
      
      def words
        words = []
        
        @tokens.find_all { |t| t[:type] == :parsed }.each do |token|
          if token[:pos] == 'POS'
            # Possessive ending, add to previous token
            words[-1].word << token[:literal]
            words[-1].lemma << token[:literal]
            words[-1].tokens << token
            next
          else
            # All other tokens
            pp token
            pos, grammar = INTERNAL_INFO_FOR_PARSED_POS[token[:pos]]
            word = Sprakd::Word.new(token[:literal], token[:lemma], pos, [token], grammar)
            words << word
          end
        end
        
        words
      end
      
      def sentences
        sentences = []
        current = ''
        
        @tokens.each do |token|
          if token[:type] == :sentence_split
            sentences << current
            current = ''
          else
            current << token[:literal]
          end
        end
        
        # In case there is no :sentence_split at the end
        sentences << current if current.length > 0

        sentences.collect { |s| s.strip! }
        sentences
      end
        
    end
  end
end

Sprakd::Manager.register(Sprakd::Provider::FreelingEn, :en, [:words, :sentences])

