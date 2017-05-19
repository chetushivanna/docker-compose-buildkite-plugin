#!/bin/bash
set -ueo pipefail

built_images=( $(get_prebuilt_images_from_metadata) )

# First, find any prebuilt images, pull them down and tag them
if [[ ${#built_images[@]} -gt 0 ]] ; then
  built_services=( $(get_services_from_map "${built_images[@]}") )

  echo "~~~ :docker: Pulling pre-built services ${built_services[*]}" >&2;
  for service in "${built_services[@]}" ; do
    if prebuilt_image=$(get_prebuilt_image "$service" "${built_images[@]}") ; then
      plugin_prompt_and_run docker pull "$prebuilt_image"
    fi
  done
fi

# Targets for pushing come in a variety of forms:

# service <- just a service name
# service:image <- a service name and a specific image name to use
# service:image:tag <- a service name and a specific image and tag to use

# A push figures out the source image from either:
# 1. An image declaration in the docker-compose config for that service
# 2. The default projectname_service image format that docker-compose uses

# Then we figure out what to push, and where
for line in $(plugin_read_list PUSH) ; do
  IFS=':' read -a tokens <<< "$line"
  service=${tokens[0]}
  service_image=$(compose_image_for_service "$service")
  prebuilt_image=

  if [[ ${#built_images[@]} -gt 0 ]] && prebuilt_image=$(get_prebuilt_image "$service" "${built_images[@]}") ; then
    echo "~~~ :docker: Tagging prebuilt image ${prebuilt_image} as ${service_image}" >&2;
    plugin_prompt_and_run docker tag "$prebuilt_image" "$service_image"
  fi

  if [[ ${#tokens[@]} -eq 1 ]] ; then
    if [[ "$service_image" == "$(default_compose_image_for_service "$service")" && -z "$prebuilt_image" ]] ; then
      echo "~~~ :docker: Skipping pushing default image $service_image" >&2;
      continue
    fi
    echo "~~~ :docker: Pushing images for $service" >&2;
    run_docker_compose push "$service"
  else
    target_image="$(IFS=:; echo "${tokens[*]:1}")"
    echo "~~~ :docker: Pushing image $target_image" >&2;
    plugin_prompt_and_run docker tag "$service_image" "$target_image"
    plugin_prompt_and_run docker push "$target_image"
  fi
done