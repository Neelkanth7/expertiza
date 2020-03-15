class TreeDisplayController < ApplicationController
  helper :application
  include SecurityHelper

  def action_allowed?
    true
  end

  def confirm
    @id = params[:id]
    @node_type = params[:nodeType]
  end

  def goto_controller(name_parameter)
    node_object = TreeFolder.find_by(name: name_parameter)
    session[:root] = FolderNode.find_by(node_object_id: node_object.id).id
    redirect_to controller: 'tree_display', action: 'list'
  end
  def goto_questionnaires() goto_controller('Questionnaires') end
  def goto_review_rubrics() goto_controller('Review') end
  def goto_metareview_rubrics() goto_controller('Metareview') end
  def goto_teammatereview_rubrics() goto_controller('Teammate Review') end
  def goto_author_feedbacks() goto_controller('Author Feedback') end
  def goto_global_survey() goto_controller('Global Survey') end
  def goto_surveys() goto_controller('Assignment Survey') end
  def goto_course_surveys() goto_controller('Course Survey') end
  def goto_courses() goto_controller('Courses') end
  def goto_bookmarkrating_rubrics() goto_controller('Bookmarkrating') end
  def goto_assignments() goto_controller('Assignments') end

  # Called by /tree_display/list
  # Redirects to proper page if user is not an instructor or TA.
  def list
    redirect_to controller: :content_pages, action: :view if current_user.nil?
    redirect_to controller: :student_task, action: :list if current_user.try(:student?)
  end

  def confirm_notifications_access
    redirect_to controller: :notifications, action: :list if current_user.try(:student?)
  end
  
  # Returns the contents of each top level folder as a json object.
  def get_folder_contents
    # Get all child nodes associated with a top level folder that the logged in user is authorized
    # to view. Top level folders include Questionaires, Courses, and Assignments.
    folders = {}
    FolderNode.get.each do |folder_node|
      child_nodes = folder_node.get_children(nil, nil, session[:user].id, nil, nil)
       # Serialize the contents of each node so it can be displayed on the UI
      contents = []
      child_nodes.each do |node|
        contents.push(serialize_folder_to_json(folder_node.get_name, node))
      end
      
      # Store contents according to the root level folder.
      folders[folder_node.get_name] = contents
    end
    
    # Sort assignments by ?
    folders['Assignments'] = folders['Assignments'].sort_by {|x| [x['instructor'], -1 * x['creation_date'].to_i] }
    respond_to do |format|
      format.html { render json: folders }
    end
  end

  # for child nodes
  def children_node_2_ng
    child_nodes = child_nodes_from_params(params[:reactParams2][:child_nodes])
    res = get_tmp_res(params, child_nodes)
    respond_to do |format|
      format.html { render json: res }
    end
  end

  # gets and renders last open tab from session
  def session_last_open_tab
    res = session[:last_open_tab]
    respond_to do |format|
      format.html { render json: res }
    end
  end

  # sets the last open tab from params
  def set_session_last_open_tab
    session[:last_open_tab] = params[:tab]
    res = session[:last_open_tab]
    respond_to do |format|
      format.html { render json: res }
    end
  end

  def drill
    session[:root] = params[:root]
    redirect_to controller: 'tree_display', action: 'list'
  end

  def filter
    qid = 'filter+'
    search = params[:filter_string]
    filter_node = params[:filternode]
    if filter_node == 'QAN'
      qid = filter_node_is_qan(search, qid)
    elsif filter_node == 'ACN'
      session[:root] = 2
      qid << search
    end
    qid
  end
  
  private
  # finding out child_nodes from params
  def child_nodes_from_params(child_nodes)
    if child_nodes.is_a? String and !child_nodes.empty?
      JSON.parse(child_nodes)
    else
      child_nodes
    end
  end
  
  # getting all attributes of assignment node
  def assignments_method(node, tmp_object)
    tmp_object.merge!(
      "course_id" => node.get_course_id,
      "max_team_size" => node.get_max_team_size,
      "is_intelligent" => node.get_is_intelligent,
      "require_quiz" => node.get_require_quiz,
      "allow_suggestions" => node.get_allow_suggestions,
      "has_topic" => SignUpTopic.where(['assignment_id = ?', node.node_object_id]).first ? true : false
    )
  end
  
  # Separates out courses based on if he/she is the TA for the course passed by marking private
  # to be true in that case
  def update_in_ta_course_listing(instructor_id, node, tmp_object)
    tmp_object["private"] = true if session[:user].role.ta? == 'Teaching Assistant' &&
        Ta.get_my_instructors(session[:user].id).include?(instructor_id) &&
        ta_for_current_course?(node)
  end

  def update_is_available(tmp_object, instructor_id, node)
    tmp_object["is_available"] = is_available(session[:user], instructor_id) || (session[:user].role.ta? &&
        Ta.get_my_instructors(session[:user].id).include?(instructor_id) && ta_for_current_course?(node))
  end

  # Ensures that instructors (who are not ta) would have update_in_ta_course_listing not changing
  # the private value if he/she is not TA which was set to true for all courses before filtering
  # in update_tmp_obj in courses_assignments_obj
  def update_instructor(tmp_object, instructor_id)
    tmp_object["instructor_id"] = instructor_id
    tmp_object["instructor"] = nil
    tmp_object["instructor"] = User.find(instructor_id).name(session[:ip]) if instructor_id
  end

  def update_tmp_obj(tmp_object, node)
    tmp = {
      "directory" => node.get_directory,
      "creation_date" => node.get_creation_date,
      "updated_date" => node.get_modified_date,
      "institution" => Institution.where(id: node.retrieve_institution_id),
      "private" => node.get_instructor_id == session[:user].id
    }
    tmp_object.merge!(tmp)
  end

  def courses_assignments_obj(node_type, tmp_object, node)
    update_tmp_obj(tmp_object, node)
    # tmpObject["private"] = node.get_private
    instructor_id = node.get_instructor_id
    ## if current user's role is TA for a course, then that course will be listed under his course listing.
    update_in_ta_course_listing(instructor_id, node, tmp_object)
    update_instructor(tmp_object, instructor_id)
    update_is_available(tmp_object, instructor_id, node)
    assignments_method(node, tmp_object) if node_type == "Assignments"
  end
  
  # Creates a json object that can be displayed by the UI
  def serialize_folder_to_json(folder_type, node)
    json = {
      "nodeinfo" => node,
      "name" => node.get_name,
      "type" => node.type
    }
    
    if folder_type == "Courses" or folder_type == "Assignments"
      json.merge! ({
        "directory" => node.get_directory,
        "creation_date" => node.get_creation_date,
        "updated_date" => node.get_modified_date,
        "institution" => Institution.where(id: node.retrieve_institution_id),
        "private" => node.get_instructor_id == session[:user].id
      })
      instructor_id = node.get_instructor_id
      update_in_ta_course_listing(instructor_id, node, json)
      update_instructor(json, instructor_id)
      update_is_available(json, instructor_id, node)
      assignments_method(node, json) if folder_type == "Assignments"
    end
    return json
  end
  
  # getting result nodes for child
  # Changes to this method were done as part of E1788_OSS_project_Maroon_Heatmap_fixes
  #
  # courses_assignments_obj method makes a call to update_in_ta_course_listing which
  # separates out courses based on if he/she is the TA for the course passed
  # by marking private to be true in that case
  #
  # this also ensures that instructors (who are not ta) would have update_in_ta_course_listing
  # not changing the private value if he/she is not TA which was set to true for all courses before filtering
  # in update_tmp_obj in courses_assignments_obj
  #
  # below objects/variable names were part of the project as before and
  # refactoring could have affected other functionalities too, so it was avoided in this fix
  #
  # fix comment end
  #
  def res_node_for_child(tmp_res)
    res = {}
    tmp_res.each_key do |node_type|
      res[node_type] = []
      tmp_res[node_type].each do |node|
        tmp_object = {
          "nodeinfo" => node,
          "name" => node.get_name,
          "type" => node.type
        }
        courses_assignments_obj(node_type, tmp_object, node) if %w[Courses Assignments].include? node_type
        res[node_type] << tmp_object
      end
    end
    res
  end

  # check if nodetype is coursenode
  def course_node_for_current_ta?(ta_mappings, node)
    ta_mappings.find {|ta_mapping| return true if ta_mapping.course_id == node.node_object_id }
    false
  end

  # check if nodetype is assignmentnode
  def assignment_node_for_current_ta?(ta_mappings, node)
    course_id = Assignment.find(node.node_object_id).course_id
    ta_mappings.each {|ta_mapping| return true if ta_mapping.course_id == course_id }
    false
  end

  # check if user is ta for current course
  def ta_for_current_course?(node)
    ta_mappings = TaMapping.where(ta_id: session[:user].id)
    return course_node_for_current_ta?(ta_mappings, node) if node.is_a? CourseNode
    return assignment_node_for_current_ta?(ta_mappings, node) if node.is_a? AssignmentNode
    false
  end

  # check if current user is ta for instructor
  def is_user_ta?(instructor_id, child)
    # instructor created the course, current user is the ta of this course.
    session[:user].role_id == 6 and
        Ta.get_my_instructors(session[:user].id).include?(instructor_id) and ta_for_current_course?(child)
  end

  # check if current user is instructor
  def is_user_instructor?(instructor_id)
    # ta created the course, current user is the instructor of this ta.
    instructor_ids = []
    TaMapping.where(ta_id: instructor_id).each {|mapping| instructor_ids << Course.find(mapping.course_id).instructor_id }
    session[:user].role_id == 2 and instructor_ids.include? session[:user].id
  end

  def update_is_available_2(res2, instructor_id, child)
    # current user is the instructor (role can be admin/instructor/ta) of this course. is_available_condition1
    res2["is_available"] = is_available(session[:user], instructor_id) ||
        is_user_ta?(instructor_id, child) ||
        is_user_instructor?(instructor_id)
  end

  # attaches assignment nodes to course node of instructor
  def coursenode_assignmentnode(res2, child)
    res2["directory"] = child.get_directory
    instructor_id = child.get_instructor_id
    update_instructor(res2, instructor_id)
    update_is_available_2(res2, instructor_id, child)
    assignments_method(child, res2) if child.type == "AssignmentNode"
  end

  # getting result nodes for child2. res[] contains all the resultant nodes.
  def res_node_for_child_2(ch_nodes)
    res = []
    if ch_nodes
      ch_nodes.each do |child|
        node_type = child.type
        res2 = {
          "nodeinfo" => child,
          "name" => child.get_name,
          "key" => params[:reactParams2][:key],
          "type" => node_type,
          "private" => child.get_private,
          "creation_date" => child.get_creation_date,
          "updated_date" => child.get_modified_date
        }
        coursenode_assignmentnode(res2, child) if %w[CourseNode AssignmentNode].include? node_type
        res << res2
      end
    end
    res
  end

  # initialising folder node 2
  def initialize_fnode_2(fnode, child_nodes)
    child_nodes.each do |key, value|
      fnode[key] = value
    end
  end

  def get_tmp_res(params, child_nodes)
    fnode = (params[:reactParams2][:nodeType]).constantize.new
    initialize_fnode_2(fnode, child_nodes)
    ch_nodes = fnode.get_children(nil, nil, session[:user].id, nil, nil)
    res_node_for_child_2(ch_nodes)
  end
  
  # if filter node is 'QAN', get the corresponding assignment questionnaires
  def filter_node_is_qan(search, qid)
    assignment = Assignment.find_by(name: search)
    if assignment
      assignment_questionnaires = AssignmentQuestionnaire.where(assignment_id: assignment.id)
      if assignment_questionnaires
        assignment_questionnaires.each {|q| qid << "#{q.questionnaire_id}+" }
        session[:root] = 1
      end
    end
    qid
  end
end
