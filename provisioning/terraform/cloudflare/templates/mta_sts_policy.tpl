version: STSv1
mode: ${mode}
%{for _,value in mx ~}
mx: ${value.host}
%{endfor ~}
max_age: ${max_age}
