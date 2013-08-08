require 'rubygems'
require 'virtual_keywords'
require 'set'

$log = []
def log(msg)
  $log << msg
  puts msg
end

log "LOADING RAILGRINDER ********************************************************************************"

class Object
  def metaclass
    class << self
      self
    end
  end
end

RailgrinderField = Struct.new(:name, :type)

$all_vcs = Hash.new
def add_vcs(controller, action, vc)
  if $all_vcs[controller] then
    $all_vcs[controller][action] = vc
  else
    $all_vcs[controller] = Hash.new
    $all_vcs[controller][action] = vc
  end
end

def add_node(graph, type, exp, conditions, controller, action)
  type_colors = ["#7192DF", "#9DB1DF"]
  exp_colors = ["#65E2A2", "#97E2BC"]
  condition_colors = ["#D1F56E", "#E0F5A4"]
  controller_colors = ["#8D9280", "#F2F7E4"]
  action_colors = ["#ffffff", "#ffffff"]

  type_node = graph.add_child(type, type_colors, true)
  exp_node = type_node.add_child(exp, exp_colors, false)

  current_node = exp_node
  conditions.each do |c|
    current_node = current_node.add_child(c, condition_colors, true)
  end

  current_node.add_child(controller, controller_colors, true).add_child(action, action_colors, true)
end


def add_node_2(graph, type, exp, conditions, controller, action)
  type_colors = ["#7192DF", "#9DB1DF"]
  exp_colors = ["#65E2A2", "#97E2BC"]
  condition_colors = ["#D1F56E", "#E0F5A4"]
  controller_colors = ["#8D9280", "#F2F7E4"]
  action_colors = ["#ffffff", "#ffffff"]

  action_node = graph.add_child(controller, controller_colors, true).add_child(action, action_colors, true)

  type_node = action_node.add_child(type, type_colors, true)
  exp_node = type_node.add_child(exp, exp_colors, true)

  current_node = exp_node
  conditions.each do |c|
    current_node = current_node.add_child(c, condition_colors, true)
  end
end


class Graph
  def initialize(data, colors=["#c6dbef","#3182bd"], open=true)
    @data = data.to_s.gsub("\"", "\'").delete("\n")
    @children = []
    @colors = colors
    @open = open
  end

  def data
    @data
  end

  def add_child(val, colors=["#c6dbef", "#c6dbef"], open=false)
    existing = @children.select{|c| c.data == val}

    if existing != [] then
      existing.first
    else 
      child = Graph.new(val, colors, open)
      @children << child
      child
    end
  end

  def children
    @children
  end

  def to_json
    if @children == [] then
      "{\"name\": \"" + @data.to_s + "\", \"open_color\": \"" + @colors[0] + "\", \"closed_color\": \"" + @colors[1] + "\"}\n"
    else
      "{\"name\": \"" + @data.to_s + " (" + @children.length.to_s + ")\",\n" +
        "\"open_color\": \"" + @colors[0] + "\", \"closed_color\": \"" + @colors[1] + "\"," +
        if @open then "\"children\": [\n" else "\"_children\": [\n" end +
        @children.map{|v| v.to_json}.join(",\n") +
        "]}\n"
    end
  end

  def depth
    if @children == [] then
      1
    else
      1 + @children.map{|x| x.depth}.max
    end
  end

  def mk_s n
    if @children == [] then
      self.data.to_s
    else
      self.data.to_s + "\n" +
        @children.map{|x| (" " * n) + " |-  " + x.mk_s(n+1)}.join("\n")
    end
  end

  def to_s
    mk_s 1
  end
end


class Class
  def descendants
    result = []
    ObjectSpace.each_object(Class) { |klass| result << klass if klass < self }
    result
  end
end

$verification_conditions = []


class UnreachableException < Exception
end


class Symbol
  include Comparable

  def <=>(other)
    self.to_s <=> other.to_s
  end
end

class RubiconAnalysis
  def initialize(&block)
    @analysis_params = {
      :search_dirs => [],
      :extra_route_args => Hash.new,
      :routes => [],
      :routes_func => lambda { raise "error: no routes function provided" },
      :current_user_func => lambda { raise "error: no current user function provided" },
      :app_path => "no path provided",
      :policies => []
    }

    instance_eval &block

    Analyzer.new(@analysis_params).run_analysis
  end

  def be_displayed
    :be_displayed
  end

  def before(&block)
    @analysis_params[:before] = block
  end

  def to_get_routes(&block)
    @analysis_params[:routes_func] = block
  end

  def to_set_current_user(&block)
    @analysis_params[:current_user_func] = block
  end

  def extra_route_args(args)
    @analysis_params[:extra_route_args] = args
  end

  def search_dir(dir)
    @analysis_params[:search_dirs] << dir
  end

  def rails_path(path)
    @analysis_params[:app_path] = path
  end

  def check(&block)
    @analysis_params[:check] = block
  end

  def policies(&block)
    @analysis_params[:policies] = block
  end
end

class Analyzer
  def initialize(analysis_params)
    @analysis_params = analysis_params
    $analyzer = self
  end

  def run_analysis
    rails_path = @analysis_params[:app_path]
    $rails_path = rails_path

    ENV["RAILS_ENV"] ||= 'test'
    $VERBOSE = nil

    log "Loading rails files"
    # require 'rails'

    # log "Patching filters"
    # old_before_filter = ActionController::Base.method(:before_filter)
    # ActionController::Base.metaclass.send(:define_method, :before_filter, lambda{|*args| 
    #                                         log "HOHO " + args.to_s
    #                                         old_before_filter.call(*args)
    #                                       })

    require File.expand_path(rails_path.to_s + "/config/environment")

    log "Loading files from extra search directories"
    @analysis_params[:search_dirs].each do |dir|    
      Dir.glob(dir + '/*.rb').each { |file| require file }
    end

#    Rails.application.eager_load!
    Dir.glob(Rails.root.to_s + '/app/models/**/*.rb').each { |file| log "loading file " + file.to_s; require file }
    activerecord_klasses = ActiveRecord::Base.descendants

    Dir.glob(Rails.root.to_s + '/app/controllers/**/*.rb').each { |file| require file }
    controller_klasses = ActionController::Base.descendants


    def get_instance_vars(binding)
      ivars = eval("self.instance_variables", binding).select{|x| !x.to_s.start_with? "@_"}
      Hash[ivars.map {|v| [v, eval("instance_variable_get(\"" + v.to_s + "\")", binding)]}]
    end

    def fix_bindings(before, after, binding, condition)
      # log "<p>FIXING ********************************************************************************</p>"
      # log "<p>before: " + before.to_s + "</p><br>"
      # log "<p>after: " + after.to_s + "</p><br>"
      # log "<p>binding: " + binding.to_s + "</p><br>"
      # log "<p>condition: " + condition.to_s + "</p><br><br>"
      # log "<p>DONE ********************************************************************************</p><br>"

      after.each_pair do |var, val|
        next unless val.is_a? Exp # TODO
#        log "VAL IS EXP; comparison: " + (before[var].equals val).to_s

        if !before[var] then
#          log "FOUND NO VALUE: " + val.to_s
          val.add_constraint(condition)
        elsif before[var].equals val then
          # nothing
        else
          #log "ADDING CHOICE: " + var.to_s + ", " + val.to_s + ", " + before[var].to_s
          before[var].add_constraint(Exp.new(:bool, :not, condition))
          val.add_constraint(condition)

          $temp1 = before[var]
          $temp2 = val

          choice = eval("instance_variable_set(:" + var.to_s + ", Choice.new($temp1, $temp2))", binding)
#          log "CHOICE: " + choice.to_s

#          choice = eval("instance_variable_set(" + var.to_s + ", Choice.new)",
#                        binding)
          #log "FOUND DIFFERENCE " + var.to_s + " : " + before[var].to_s + ", " + val.to_s

          # RIGHT HERE IS WHERE WE NEED TO DO SOMETHING LEGIT!!!!!!!1
          #raise "ERROR: Not an addition!!"
          
          #val.add_constraint(condition)
        end
      end
    end

    $conditions = []
    $ifs = 0
    log "Initializing keyword virtualizers"
    controller_virtualizer = VirtualKeywords::Virtualizer.new(:for_subclasses_of => [ActionController::Base])

    controller_virtualizer.virtual_if do |condition, then_do, else_do|
      $ifs = $ifs + 1
      redirect = false
      
      c = condition.call

      ivars_before = get_instance_vars(condition.binding)
#      log "BEFORE: " + ivars_before.to_s

      begin
        then_result = then_do.call
      rescue UnreachableException
        log "UNREACHABLE: first branch"
        redirect = Exp.new(:bool, :not, c)
      rescue Exception => e
        log "FAILURE: " + e.to_s
      end

      ivars_middle = get_instance_vars(condition.binding)
      fix_bindings(ivars_before, ivars_middle, condition.binding, c)

      begin
        else_result = else_do.call
      rescue UnreachableException
        log "UNREACHABLE: second branch"
        if redirect then
          raise UnreachableException
        else
          redirect = c
        end
      rescue Exception => e
        log "FAILURE: " + e.to_s
      end

      ivars_end = get_instance_vars(condition.binding)
      fix_bindings(ivars_middle, ivars_end, condition.binding, Exp.new(:bool, :not, c))

      if redirect then
        $path_constraints << redirect
        log "ADDING REDIRECT: " + redirect.to_s
        # ivars_end.each_pair do |var, val|
        #   if val.is_a? Exp then
        #     val.add_constraint(redirect)
        #   else
        #     log "IVAR is not an expression!"
        #   end
        # end
      end

      $conditions << c
      Exp.new(:if, c, then_result, else_result)
    end


    log "Loading class redefinitions..."
    require File.expand_path(File.dirname(__FILE__) + '/class_redefinitions')
    require File.expand_path(File.dirname(__FILE__) + '/alloy_translation')

    log "done."

    # ********************************************************************************

    # structure to describe fields, and a global var to hold them
    $class_fields = Hash.new

    def add_class_field(klass, name, type)
      # puts "adding class field: " + klass.to_s + ", " + name.to_s + ", " + type.to_s
      # puts "type of class is : " + klass.class.to_s
      field = RailgrinderField.new(name, type)

      if $class_fields[klass] then
        $class_fields[klass] << field
      else
        $class_fields[klass] = [field]
      end
    end

    activerecord_methods = ActiveRecord::Base.methods
    log "Redefining ActiveRecord Classes"
    activerecord_klasses.each do |klass|
      klass_name = klass.to_s
      klass_methods = klass.methods - activerecord_methods

      log "working on class " + klass_name
      log "methods: "

      log "originally " + klass.methods.length.to_s + ", reduced to " + klass_methods.length.to_s
      # klass_methods.each do |m|
      #   log "&nbsp;&nbsp;" + m.to_s
      # end

      # build a structure describing all the fields and their types
      begin
        klass.columns.each do |column|
          add_class_field(klass_name, column.name, column.type)
        end
        
        klass.reflect_on_all_associations.each do |assoc|
          add_class_field(klass_name, assoc.name, assoc.name.to_s.singularize.capitalize)
        end
      rescue => msg  
        log "    ERROR: Something went wrong ("+msg.to_s+")"  
      end 
      
      # replace the class with an expression so that all calls to the class methods are expressions
      log "replacing class definitions"
      new_klass = Exp.new(klass_name, klass_name)
      new_klass.send(:define_method, :controller_name, lambda { klass_name })

      klass_methods.each do |m|
        old_method = klass.method(m)
        new_klass.metaclass.send(:define_method, m, lambda{|*args|
                                   log "HOHA: " + m.to_s
                                   old_method.call(*args)
                                 })
      end

      #replace_defs(klass, new_klass)

      fst, snd = klass.to_s.split("::")
      if snd then
        fst.constantize.const_set(snd, new_klass)
      else
        Object.const_set(klass.to_s, new_klass)
      end
    end


    log "Running analysis..."

    if @analysis_params[:before] then @analysis_params[:before].call end
    require 'rspec/rails'

    def test_one_action(controller, action)
      log "Running " + controller.to_s + " / " + action.to_s

      $track_to_s = false
      $to_s_exps = []
      $callback_conditions = []
      $path_constraints = []

      p = controller.new

      if p.method(action).arity != 0 then
        return Hash.new
      end

      # TODO: do we still need these?
      [:@_routes, :@_controller, :@_request, :@_response].each do |v|
        p.instance_variable_set(v, Exp.new(:unused, v))
      end

      request = ActionController::TestRequest.new
      env = SymbolicArray.new
      ActionController::TestRequest.send(:define_method, :env, proc { env })
      controller.send(:define_method, :request, proc {request})

      # [:request].each do |v|
      #   controller.send(:define_method, v, proc {Exp.new(v, v)})
      # end
      
      current_user = Exp.new(:User, :current_user)
      @analysis_params[:current_user_func].call(current_user)
      # this is specific...
      controller.send(:define_method, :authenticate_user, proc { @user = current_user })

      my_params = SymbolicArray.new
      controller.send(:define_method, :params, proc {my_params})
      controller.send(:define_method, :action_name, proc {action.to_s.dup})
      controller.send(:define_method, :redirect_to, lambda {|*args| raise UnreachableException })
      controller.send(:define_method, :assert_is_devise_resource!, proc { log "Assertion..."})

      # todo: spec the rest of these
      if defined? CanCan then
        CanCan::ControllerResource.send(:define_method, :load_and_authorize_resource, 
                                        proc { log "LOADINGG";
                                          name = @controller.class.to_s.sub("Controller", "").singularize.downcase
                                          type = name.camelize.to_s.to_sym;
                                          result = Exp.new(type, type, :find, Exp.new(:params, :id));
                                          result.add_constraint(Exp.new(:bool, :CanCan_authorized))
                                          log "NAME " + "@" + name.to_s;
                                          log "OUTPUT " + result.to_s;
                                          @controller.instance_variable_set("@" + name.to_s, result) })
      end

      # ActionController::Base.metaclass.class_eval do
      #   def __run_callback(key, kind, object, &blk) #:nodoc:
      #     name = __callback_runner_name(key, kind)
      #     log "CALLBACK " + name.to_s + ", " + key.to_s + ", " + kind.to_s + ", " + object.to_s
      #     unless object.respond_to?(name, true)
      #       str = object.send("_#{kind}_callbacks").compile(key, object)
      #       class_eval <<-RUBY_EVAL, __FILE__, __LINE__ + 1
      #       def #{name}() #{str} end
      #         protected :#{name}
      #         RUBY_EVAL
      #     end
      #     result = object.send(name, &blk)
      #     log "CALLBACK RESULT: " + result.to_s
      #     $callback_conditions << result
      #     result
      #   end
      # end

      old_render = controller.instance_method(:render_to_body)
      controller.send(:define_method, :render_to_body, lambda{|*args|
                        log "RENDERING"
                        $track_to_s = true
                        my_render = old_render.bind(self)
                        begin
                          my_render.call(*args)
                          log "  RENDERING SUCCESSFUL"
                        rescue Exception => e
                          log "  RENDERING EXCEPTION"
                        end
                        $track_to_s = false
                      })

      ActionController::Rendering.send(:define_method, :render, lambda{|*args|
                                         puts "THE ARGS ARE " + args.to_s
                                         super(*args)
                                         self.content_type ||= Mime[lookup_context.rendered_format].to_s
                                         response_body
                                       })

      # timezone hack
      ActiveSupport::TimeZone.metaclass.send(:define_method, :[], lambda{|*args| Exp.new(:TimeZone, :timezone_of, *args)})
      # wish I didn't have to...
      #Devise::Mapping.metaclass.send(:define_method, :find_scope!, lambda{|*args| Exp.new(:Scope, :scope_of, *args)})
      
      vars_before = p.instance_variables
      r = p.send(:process_action, action)

      vars_after = p.instance_variables

      assign_vars = vars_after.select{|x| ! x.to_s.start_with? "@_"}
      assign_vals = assign_vars.map{|v| p.instance_variable_get(v)}

      $to_s_exps.each do |e|
          if e.is_a? Exp then
            $path_constraints.each do |c|
              e.add_constraint(c)
            end
            # $callback_conditions.each do |c|
            #   e.add_constraint(c)
            # end
          end
      end

      def flatten_choice(c)
        if c.is_a? Choice then
          flatten_choice(c.left) + flatten_choice(c.right)
        else
          [c]
        end
      end
      
      $to_s_exps = $to_s_exps.map{|e| flatten_exp(e)}.flatten(1)
      $to_s_exps.each do |e|
        consolidate_constraints(e)
      end

      $to_s_exps
    end

    results = Hash.new
    controller_klasses = ActionController::Base.descendants
#    controller_klasses = [] # remove
    controller_klasses.each do |controller|
      controller.action_methods.each do |action|
        begin
          log "START"
          assign_vals = test_one_action(controller, action)
          results[controller.to_s + "/" + action.to_s] = assign_vals if assign_vals != []
        rescue UnreachableException => e
          log "UNREACHABLE"
          # unreachable...do nothing
        rescue Exception => e
          log "ERROR: couldn't do this one: " + e.to_s
          e.backtrace.each do |line|
            log "ERROR: " + line.to_s
          end
        end
      end
    end

    log "done ********************************************************************************"

    graph = Graph.new("ActiveRecord", colors=["#536F05", "#536F05"])
    graph2 = Graph.new("ActionController", colors=["#536F05", "#536F05"])

    results.each_pair do |controller_action, values|
      controller, action = controller_action.split("/")
      trans_vc = []

      values.each do |v|
        begin
          translated = v.to_alloy
          constraints = v.constraints.map{|c| c.to_alloy}
          add_node(graph, v.type.to_s, translated, constraints, controller, action)
          add_node_2(graph2, v.type.to_s, translated, constraints, controller, action)
        rescue => msg
          log "ERROR: couldn't translate " + v.to_s
          log "problem: " + msg.to_s
        end
      end
    end

    # log "CONDITIONS ********************************************************************************"

    # $conditions.each do |c|
    #   log " " + c.to_alloy.to_s
    # end

    # log "DONE ********************************************************************************"

    
    File.open(File.expand_path(File.dirname(__FILE__) + '/viz/graph.json'), 'w') do |file| 
      file.write graph.to_json
    end

    File.open(File.expand_path(File.dirname(__FILE__) + '/viz/graph2.json'), 'w') do |file| 
      file.write graph2.to_json
    end

    log graph.to_s

    log ''
    log "Graph depth: " + graph.depth.to_s
    log "Used " + $ifs.to_s + " ifs"

    log "Starting web server..."
    log "When it's done, please browse to http://localhost:8000"
    log ""

    require 'webrick'
    root = File.expand_path(File.dirname(__FILE__) + '/viz/')
    cb = lambda do |req, res| 
      req.query[:graph_string] = graph.to_s
      req.query[:rails_root] = Rails.root.to_s
      req.query[:log] = $log
    end
    server = WEBrick::HTTPServer.new :Port => 8000, :DocumentRoot => root, :MimeTypes => {'rhtml' => 'text/html'}, :RequestCallback => cb

    trap 'INT' do server.shutdown end

    server.start

    log ""
    log "All done!"
  end
end

