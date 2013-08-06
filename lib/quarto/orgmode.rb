require 'forwardable'

module Quarto
  class Orgmode
    include Rake::DSL

    ORG_EXPORT_ASYNC     = "nil"
    ORG_EXPORT_SUBTREE   = "nil"
    ORG_EXPORT_VISIBLE   = "nil"
    ORG_EXPORT_BODY_ONLY = "t"
    ORG_EXPORT_ELISP     = <<END
(progn
  (setq org-html-htmlize-output-type 'css)
  (org-mode)
  (message (concat "Org version: " org-version))
  (cd "<%= main.export_dir %>")
  (org-html-export-to-html
    <%= ORG_EXPORT_ASYNC %> <%= ORG_EXPORT_SUBTREE %>
    <%= ORG_EXPORT_VISIBLE %> <%= ORG_EXPORT_BODY_ONLY %>
    (quote (<%= orgmode_export_plist %>)))
  (kill-emacs))
END

    module BuildExt
      extend Forwardable

      attr_accessor :orgmode

      def_delegators :orgmode,
                     :export_from_orgmode,
                     :normalize_orgmode_export
    end

    fattr(:emacs_load_path) {
      FileList[orgmode_lisp_dir]
    }

    attr_reader :main

    def initialize(main)
      @main = main
    end

    def enhance_build(build)
      build.extend(Quarto::Orgmode::BuildExt)
      build.orgmode = Quarto::Orgmode.new(build)
      build.extensions_to_source_formats["org"] = "orgmode"
    end

    def define_tasks
      namespace :orgmode do
        task :vendor => vendor_dir
      end

      directory vendor_dir =>
        "#{main.vendor_dir}/org-#{version}.tar.gz" do |t|

        cd main.vendor_dir do
          sh "tar -xzf org-#{version}.tar.gz"
        end
        cd vendor_dir do
          sh "make"
        end
      end

      file "#{main.vendor_dir}/org-#{version}.tar.gz" =>
        main.vendor_dir do |t|
        cd main.vendor_dir do
          sh "wget http://orgmode.org/org-#{version}.tar.gz"
        end
      end
    end

    def version
      "8.0.7"
    end

    def orgmode_lisp_dir
      "#{vendor_dir}/lisp"
    end

    def orgmode_export_plist
      %W[
          :with-toc             nil
          :headline-levels      6
          :section-numbers      nil
          :language             #{main.language}
          :htmlized-source      nil
          :html-postamble       nil
          :with-sub-superscript nil
        ].join(" ")
    end

    def vendor_dir
      "#{main.vendor_dir}/org-#{version}"
    end

    def export_from_orgmode(export_file, source_file)
      language = language
      elisp = ERB.new(ORG_EXPORT_ELISP).result(binding)
      sh "emacs", *emacs_flags, *%W[--file #{source_file} --eval #{elisp}]
    end

    def emacs_flags
      emacs_load_path_flags = emacs_load_path.pathmap("--directory=%p")
      ["--batch", *emacs_load_path_flags]
    end

    def normalize_orgmode_export(export_file, section_file)
      main.normalize_generic_export(export_file, section_file) do |normal_doc|
        listing_pre_elts = normal_doc.css("div.org-src-container > pre.src")
        listing_pre_elts.each do |elt|
          language = elt["class"].split.grep(/^src-(.*)$/) do
            break $1
          end
          elt.parent.replace(normal_doc.create_element("pre") do |pre_elt|
              pre_elt["class"] = "sourceCode #{language}"
              pre_elt.add_child(normal_doc.create_element("code", elt.text))
            end)
        end
        figure_elts = normal_doc.css("div.figure")
        figure_elts.each do |elt|
          img_elt = elt.css("img")
          caption = elt.at_css("p:nth-child(2)").content
          elt.replace(normal_doc.create_element("figure") do |fig_elt|
              fig_elt.add_child(img_elt)
              fig_elt.add_child(normal_doc.create_element("figcaption", caption))
            end)
        end
      end
    end
  end
end