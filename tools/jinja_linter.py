#!/usr/bin/env python3

from jinja2 import Environment, meta

template_source = open("your_template.j2").read()
env = Environment()
parsed_content = env.parse(template_source)
print(meta.find_undeclared_variables(parsed_content))

