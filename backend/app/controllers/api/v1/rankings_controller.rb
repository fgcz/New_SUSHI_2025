module Api
  module V1
    # Job counts per submitter. Legacy has no such page — this is New SUSHI's
    # own, so the shape is defined here rather than ported.
    #
    # A "submission" is a job that produced a dataset in one of the caller's
    # authorized projects. Counting through the output dataset keeps it to one
    # join and one row per job; counting input datasets too would double-count
    # every job whose input and output are both in scope.
    class RankingsController < BaseController
      LIMIT = 20

      # GET /api/v1/rankings
      def index
        numbers = authorized_project_numbers.map(&:to_i)
        return render json: { rankings: [] } if numbers.empty?

        scope = Job.joins(:data_set)
                   .joins('INNER JOIN projects ON projects.id = data_sets.project_id')
                   .where(projects: { number: numbers })

        totals = scope.group(:user).count
        this_month = scope.where('jobs.created_at >= ?', Time.current.beginning_of_month)
                          .group(:user).count

        rankings = totals.map do |login, total|
          {
            username: login.presence || 'unknown',
            jobsThisMonth: this_month[login].to_i,
            totalSubmissions: total
          }
        end

        render json: {
          rankings: rankings.sort_by { |r| [-r[:jobsThisMonth], -r[:totalSubmissions], r[:username]] }.first(LIMIT)
        }
      end
    end
  end
end
