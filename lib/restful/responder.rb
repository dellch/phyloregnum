module Restful
  module Responder
    PARAM_TYPES = [ :conditions, :limit, :offset, :select, :include, :order ]

    protected

    def render (*args, &block)
      case args.first
      when Hash
        if(to_render = args.first[:json])
          case to_render
          when ActiveRecord::Relation, ActiveRecord::Base
            args.first[:json] = Restful::Formatters::JsonFormatter.new.format(to_render, prepare(params, for: :formatter))
          end
          super
        elsif(to_render = args.first[:csv])
          args.delete(:csv)
          #          args.first[:text] = CsvExporter::Export.export_to_csv(to_render, params)
          send_data CsvExporter::Export.export_to_csv(to_render, params[:select]),
            :type => 'text/csv; charset=utf-8; header=present',
            :disposition => "attachment",
            :filename => "tolkin_report.csv"
        else
          super
        end
      else
        super
      end
    end

    def new(a_collection)
      a_collection = a_collection.where('')
      validate_text_params && parse_params
      @model_class = a_collection.klass
      model_name = @model_class.to_s.demodulize
      result = a_collection.new
      instance_variable_set("@#{model_name.underscore}".to_sym, result)
      respond_to do |format|
        format.html { render 'new', layout: request.xhr? ? false : true }
        format.json { render json: result.to_json(params) }
      end
    end


    ######## OLD SHOW ############# need to merge with newer one
    #    def show(a_collection)
    #      a_collection = a_collection.where('')
    #      validate_text_params && parse_params
    #      @model_class = a_collection.klass # empty where is hack to return Relation object which can be klassed
    #      model_name = @model_class.to_s.demodulize
    #      result = a_collection.find(params[:id], params_for_find(@model_class))
    #      instance_variable_set("@#{model_name.underscore}".to_sym, result)
    #      respond_to do |format|
    #        format.html { render 'show', layout: request.xhr? ? false : true }
    #        format.json { render json: result.to_json(params) }
    #      end
    #    end
    #    alias_method :respond_to_show_request, :show
    ######### END OLD SHOW ##############

    ######## NEW SHOW ##################
    def show resource
      @resource = resource
      validate(params) && parse(params)
      result = resource.find(params[:id], prepare(params, for: :finder))
        instance_variable_set("@#{resource.member_name}", result)
        respond_to do |format|
          format.html { render 'show', layout: request.xhr? ? false : true }
          format.json { render json: result }
          format.xml  { render xml:  result.to_xml(params) }
        end
      end
      alias_method :respond_to_show_request, :show
      ######## END NEW SHOW #################

      def index resource
        @resource = resource
        filter_select if request.format.csv?
        validate(params) && parse(params)

        result = resource.scoped.apply_finder_options(prepare(params, for: :finder))
          instance_variable_set("@#{resource.collection_name}", result)
          respond_to do |format|
            format.html { render 'index', layout: !request.xhr? }
            format.json { render json: result }
            format.csv  { render csv:  result }
            format.xml  { render xml:  result.to_xml(params) }
            format.rss
          end
        end
        alias_method :respond_to_index_request_searchlogic, :index


        ######### OLD INDEX ##########################
        #    def index(a_collection)
        #      a_collection = a_collection.where('')
        #      validate_text_params && parse_params
        #      model_class = a_collection.where('').klass # empty where is hack to return Relation object which can be klassed
        #      model_name = model_class.to_s.demodulize
        #      @collection = a_collection.collection
        #  #    filter_select if request.format.csv?
        #      @collection.load(params)
        #      instance_variable_set("@#{model_name.underscore.pluralize}".to_sym, @collection)
        #  #    @collection.load(parse_finder_params(model_class))
        #      yield(@collection) if block_given?
        #      respond_to do |format|
        #        format.html
        #        format.csv  {
        #          send_data @collection.to_csv(params[:select]),
        #          :type => 'text/csv; charset=utf-8; header=present',
        #          :disposition => "attachment",
        #            :filename => "tolkin_report.csv"
        #        }
        #        format.json { render json: @collection.to_json(params), status: :ok }
        #        format.xml  { render :xml => @collection.to_xml(params) }
        #        format.rss
        #      end
        #    end
        ######### END OLD INDEX #####################



        def filter_select
          @old_select = params[:select];
          @new_select = []
          params[:select].each do |col_name|
            col_name.gsub!('_label','.label')
          end
          params.delete("select");
        end

        #  def selected_col
        #    @old_select
        #        end

        def handle_save_search(object, search_params)
          if(params[:tag] && params[:tag][:save] && params[:tag][:name].strip != "")
            saved_search = object.save_search(search_params, current_project, current_user, params[:tag][:name])
            flash["notice"] = "Search Saved as Tag: #{ params[:tag][:name]}"
          end
        end

        #  def respond_to_index_request(object)
        #    @requested = object.find(:all, parse_finder_params)
        #    @count = object.count
        #    yield if block_given?
        #    respond_to do |format|
        #      format.js { render :json => "{ 'count': #{@count}, 'requested': #{@requested.to_json(parse_formatter_params)} }" }
        #      format.xml { render :xml => @requested.to_xml(parse_formatter_params) }
        #      format.html
        #      format.rss
        #    end
        #  end

        def respond_to_create_request
          start_vals = params[controller_name.singularize.to_sym]
          namespace = self.class.to_s.split('::')[0..-2].join('::')
          model_name = controller_name.singularize.camelize
          model = [namespace, model_name].join('::').constantize
          start_vals = process_update_fields(start_vals, model)
          model.create! start_vals

          respond_to do |format|
            format.html { redirect_to :back }
            format.js   { head :ok }
          end
        end

        def respond_to_update_request  #(object)
          #    @to_update = object.find(params[:id])
          #    form_fields = params[ActionController::RecordIdentifier.singular_class_name(@to_update).to_sym]
          namespace = self.class.to_s.split('::')[0..-2].join('::')
          model_name = controller_name.singularize.camelize
          model = [namespace, model_name].join('::').constantize
          object = model.first(:conditions => ["#{model.primary_key} = ? and project_id = ?", params[:id], current_project.id ])
          vals = params[controller_name.singularize.to_sym]
          vals = process_update_fields(vals, model)
          object.update_attributes! vals
          yield(object) if block_given?
          #    @to_update.update_attributes!(form_fields)
          respond_to do |format|
            format.js   { head :ok }
            format.json { head :ok }
            format.xml  { head :ok }
            format.html {
              flash["notice"] = 'Saved successfully.'
              redirect_to :back
            }
          end
        end
        alias :update :respond_to_update_request

        def respond_to_has_many_relation_request(object, relation)
          model_class=object.name
          options = params_for_find (model_class)
          @requested = object.find(params[:id]).send(relation).find(:all, options)
          respond_to do |format|
            format.js { render :json => @requested }
            format.xml { render :xml => @requested }
            format.rss { render :template => relation + ".rss.builder" }
          end
        end

        def process_update_fields(fields, model)
          # set blank fields to nil
          fields.each do |(k,v)|
            fields[k] = [*v].first
          end
          fields.each_pair do |key, value|
            fields[key] = nil if value.strip.blank?
          end
          fields = model.columns.inject(fields) do |flds, column|
            case column.type
            when :date then process_date_attribute(fields, column.name)
            else fields
            end
          end
        end

        def process_date_attribute form_fields, field_name
          # process dates
          y = form_fields.delete("#{field_name.to_s}_Y")
          mm = form_fields.delete("#{field_name.to_s}_mm")
          dd = form_fields.delete("#{field_name.to_s}_dd")
          if(y.blank? || mm.blank? || dd.blank? )
            form_fields[field_name] = nil
          else
            form_fields[field_name] = "#{y}-#{mm}-#{dd}"
          end
          form_fields
        end

        def process_boolean_attribute form_fields, field_name # add column = false declaration where no form field value returned
          form_fields[field_name] = form_fields[field_name] ? true : false
          form_fields
        end


        def validate params
          @validator ||= Restful::Validator.new
          PARAM_TYPES.each do |param_type| # run validator
            @validator.validate(params[param_type], param_type) if params[param_type] && params[param_type].kind_of?(String)
          end
        end

        def parse params
          @parser ||= Restful::Parser.new
          PARAM_TYPES.each do |param_type|
            params[param_type] = @parser.parse(params, param_type) if params[param_type]
          end
        end

        def prepare params, options
          Restful::Preparer.new(resource: @resource).prepare(params, options)
        end

        def validate_text_params
          validate params
        end

        def parse_params
          parse params
        end

        def query_params_provided?
          !!params[:select]
        end

        def parse_formatter_params_for_people
          #@collection=  SyncCollection.new({ type: Person, search: Person})
          model_class = Person
          #model_class = (@collection.respond_to?(:first) ? @collection.try(:first) : @collection).try(:class)
          if(model_class) # don't need json/xml formatting options for empty array of results
            formatter = Restful::Formatter.new(Person)
            formatter.format(params)
          else
            {}
          end
        end
      end
    end
