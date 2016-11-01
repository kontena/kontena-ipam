

namespace :release do
  VERSION = Gem::Version.new(File.read('VERSION').strip)
  NAME = 'kontena-docker-ipam-plugin'
  DOCKER_NAME = 'kontena/ipam-plugin'
  if VERSION.prerelease?
    DOCKER_VERSIONS = ['edge']
  else
    DOCKER_VERSIONS = ['latest', VERSION.to_s.match(/(\d+\.\d+)/)[1]]
  end

  desc 'Build all'
  task :build => [:build_docker] do

  end

  desc 'Build docker images'
  task :build_docker => :environment do
    sh("docker rmi #{DOCKER_NAME}:#{VERSION} || true")
    sh("docker build --no-cache --pull -t #{DOCKER_NAME}:#{VERSION} .")
    DOCKER_VERSIONS.each do |v|
      sh("docker rmi #{DOCKER_NAME}:#{v} || true")
      sh("docker tag #{DOCKER_NAME}:#{VERSION} #{DOCKER_NAME}:#{v}")
    end
  end

  desc 'Push docker images'
  task :push_docker => :environment do
    sh("docker push #{DOCKER_NAME}:#{VERSION}")
    DOCKER_VERSIONS.each do |v|
      sh("docker push #{DOCKER_NAME}:#{v}")
    end
  end
end
