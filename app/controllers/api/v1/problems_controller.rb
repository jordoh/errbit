class Api::V1::ProblemsController < ApplicationController
  respond_to :json, :xml

  skip_before_action :authenticate_user!
  before_action :require_api_key_or_authenticate_user!

  FIELDS = %w{_id app_id app_name environment hosts message where first_notice_at last_notice_at resolved resolved_at notices_count}

  def show
    problem = benchmark("[api/v1/problems_controller/show] query time") do
      begin
        problems_scope.only(FIELDS).find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        head :not_found
        return false
      end
    end

    attributes = problem.attributes

    if (err = problem.errs.last) && (notice = err.notices.last) && (backtrace = notice.backtrace)
      attributes["backtrace"] = backtrace.lines
    end
    attributes.merge!(comments: problem.comments.map(&:_id))

    respond_to do |format|
      format.any(:html, :json) { render json: attributes } # render JSON if no extension specified on path
      format.xml { render xml: attributes }
    end
  end

  def index
    query = {}

    if params.key?(:start_date) && params.key?(:end_date)
      start_date = Time.parse(params[:start_date]).utc
      end_date = Time.parse(params[:end_date]).utc
      query = { :first_notice_at => { "$lte" => end_date }, "$or" => [{ resolved_at: nil }, { resolved_at: { "$gte" => start_date } }] }
    end

    if params.key?(:started_after)
      started_after_query = { "$gt" => Time.parse(params[:started_after]).utc }
      if query[:first_notice_at]
        query["$and"] = (Array.wrap(query.delete(:first_notice_at)) + [ started_after_query ]).map do |first_notice_at_query|
          { first_notice_at: first_notice_at_query }
        end
      else
        query[:first_notice_at] = started_after_query
      end
    end

    if params.key?(:started_before)
      started_before_query = { "$lt" => Time.parse(params[:started_before]).utc }
      if query[:first_notice_at]
        query["$and"] = (Array.wrap(query.delete(:first_notice_at)) + [ started_before_query ]).map do |first_notice_at_query|
          { first_notice_at: first_notice_at_query }
        end
      else
        query[:first_notice_at] = started_before_query
      end
    end

    results = benchmark("[api/v1/problems_controller/index] query time") do
      problems_scope.where(query).with(:consistency => :strong).only(FIELDS).page(params[:page]).per(20).to_a
    end

    respond_to do |format|
      format.any(:html, :json) { render json: JSON.dump(results) } # render JSON if no extension specified on path
      format.xml { render xml: results }
    end
  end

protected

  def problems_scope
    @app && @app.problems || Problem
  end
end
